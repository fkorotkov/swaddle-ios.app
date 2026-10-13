import AppIntents
import SwiftUI
import WidgetKit

struct QuickLogEntry: TimelineEntry {
    var date: Date
    var child: CachedChild?
    var canRecord: Bool
    var actionURLs: [WidgetQuickAction: URL] = [:]
    var isPreview = false
    var asOf: Date? = nil
    var unit: VolumeUnit = .ml
    var pumps: [CachedPumpSession]? = nil

    static func make(childIdentifier: String?, cache: WidgetSnapshot?, unit: VolumeUnit,
                     signingKey: Data?, at date: Date, source: WidgetQuickLogSource) -> Self {
        // Never resolve a missing or removed target to another child.
        let child = cache?.children.first { "\($0.familyID)/\($0.id)" == childIdentifier }
        var entry = Self(date: date, child: child, canRecord: cache?.canRecord == true,
                         asOf: cache?.asOf, unit: unit, pumps: cache?.pumps)
        if let child, let actorID = cache?.actorID, let signingKey, entry.canRecord {
            entry.actionURLs = WidgetQuickLogCommand.links(target: "\(child.familyID)/\(child.id)", actorID: actorID,
                source: source, receipts: child.quickLogs ?? [:], signingKey: signingKey, at: date)
        }
        return entry
    }
}

struct QuickLogProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry {
        QuickLogEntry(date: .now, canRecord: false, isPreview: true)
    }
    func snapshot(for configuration: SelectChildIntent, in context: Context) async -> QuickLogEntry {
        var entry = entry(for: configuration, at: .now, source: source(in: context))
        entry.isPreview = context.isPreview
        return entry
    }
    func timeline(for configuration: SelectChildIntent, in context: Context) async -> Timeline<QuickLogEntry> {
        let current = entry(for: configuration, at: .now, source: source(in: context))
        // Expire Undo using a timeline, not a view timer. A delayed system refresh remains safe:
        // the intent also checks the deadline and the original revision before deleting anything.
        let expirations = Set((current.child?.quickLogs?.values ?? Dictionary<String, WidgetQuickLogReceipt>().values)
            .map(\.undoUntil).filter { $0 > current.date }).sorted()
        let future = expirations.map { entry(for: configuration, at: $0, source: source(in: context)) }
        return Timeline(entries: [current] + future, policy: .after(current.date.addingTimeInterval(900)))
    }
    private func source(in context: Context) -> WidgetQuickLogSource {
        context.family == .accessoryCircular ? .lockScreen : .homeScreen
    }
    private func entry(for configuration: SelectChildIntent, at date: Date, source: WidgetQuickLogSource) -> QuickLogEntry {
        QuickLogEntry.make(childIdentifier: configuration.child?.id, cache: WidgetCache.read(),
                           unit: WidgetCache.unit, signingKey: WidgetCache.signingKey, at: date, source: source)
    }
}

struct QuickLogWidgetView: View {
    let action: WidgetQuickAction
    let entry: QuickLogEntry
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins

    private var target: String? { entry.child.map { "\($0.familyID)/\($0.id)" } }
    private var receipt: WidgetQuickLogReceipt? {
        guard let receipt = entry.child?.quickLogs?[action.rawValue], receipt.canUndo(at: entry.date) else { return nil }
        return receipt
    }
    private var failure: String? { target.flatMap { WidgetCache.quickLogFailure(target: $0, action: action.rawValue) } }
    private var childLabel: String {
        guard !redactionReasons.contains(.privacy), let child = entry.child else { return String(localized: "the configured child") }
        return child.name
    }
    private var destination: URL {
        QuickLogControl(action: action, entry: entry).destination
    }
    var body: some View {
        Group {
            if family == .systemSmall {
                HomeQuickLogSingleView(action: action, entry: entry).padding(margins)
            } else {
                lockScreenBody
            }
        }
        .containerBackground(for: .widget) {
            if family == .systemSmall { Color(uiColor: .secondarySystemGroupedBackground) }
            else { Color.clear }
        }
        .widgetURL(destination)
    }
    private var lockScreenBody: some View {
        Group {
            if entry.isPreview {
                face(label: action.title)
            } else if target != nil, entry.canRecord {
                if failure != nil {
                    face(label: String(localized: "Open"), status: "exclamationmark")
                        .accessibilityLabel("Action needs attention. Open Swaddle for details")
                } else if action == .bottle {
                    face(label: String(localized: "Bottle"))
                        .accessibilityLabel("Record a bottle for \(childLabel)")
                        .accessibilityHint("Opens the previous amounts for review. Nothing is saved until you tap Save.")
                } else if entry.actionURLs[action] == nil {
                    face(label: String(localized: "Open"), status: "arrow.up.forward.app")
                        .accessibilityLabel("Open Swaddle to refresh this widget")
                } else if receipt != nil {
                    face(label: String(localized: "Undo"), status: "checkmark")
                        .accessibilityLabel("\(action.title) saved for \(childLabel). Open Swaddle and undo this entry")
                } else {
                    face(label: action.title)
                        .accessibilityLabel("Record \(action == .both ? String(localized: "pee and poo") : action.title.lowercased()) for \(childLabel)")
                        .accessibilityHint("Opens Swaddle and saves one diaper change now. Undo is available in the app.")
                }
            } else {
                face(label: entry.child == nil ? String(localized: "Set up") : String(localized: "Open"), status: entry.child == nil ? "gearshape" : "lock")
                    .accessibilityLabel(entry.child == nil ? String(localized: "Set up this widget. Choose a child in Edit Widget.") : String(localized: "Open Swaddle to check family access"))
            }
        }
        .accessibilityAddTraits(.isButton)
        // accessoryCircular has one launch target. Its whole surface must carry the command;
        // an inner Button can be inactive while locked and the old fallback only opened Today.
    }
    private func face(label: String, status: String? = nil) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 2) {
                Group {
                    if let status { Image(systemName: status) }
                    else {
                        switch action {
                        case .pee: Image(systemName: "drop.fill")
                        case .poo: Image(systemName: "circle.hexagongrid.fill")
                        case .both:
                            HStack(spacing: 1) {
                                Image(systemName: "drop.fill")
                                Image(systemName: "circle.hexagongrid.fill")
                            }.font(.system(size: 16, weight: .semibold))
                        case .bottle: Image(systemName: "waterbottle.fill")
                        }
                    }
                }
                .font(.system(size: 23, weight: .medium))
                .frame(height: 25)
                Text(label).font(.system(.caption2, design: .rounded, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }.padding(4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(.circle)
    }
}

private func quickLogConfiguration(_ action: WidgetQuickAction, name: String, description: String) -> some WidgetConfiguration {
    AppIntentConfiguration(kind: "SwaddleQuickLog.\(action.rawValue)", intent: SelectChildIntent.self, provider: QuickLogProvider()) { entry in
        QuickLogWidgetView(action: action, entry: entry)
    }
    .configurationDisplayName(name)
    .description(description)
    .supportedFamilies([.accessoryCircular, .systemSmall])
    .contentMarginsDisabled()
}

struct PeeLockScreenWidget: Widget {
    var body: some WidgetConfiguration { quickLogConfiguration(.pee, name: String(localized: "Pee"), description: String(localized: "Open Swaddle and save a wet diaper now, with Undo if needed.")) }
}
struct PooLockScreenWidget: Widget {
    var body: some WidgetConfiguration { quickLogConfiguration(.poo, name: String(localized: "Poo"), description: String(localized: "Open Swaddle and save a soiled diaper now, with Undo if needed.")) }
}
struct BothLockScreenWidget: Widget {
    var body: some WidgetConfiguration { quickLogConfiguration(.both, name: String(localized: "Pee + poo"), description: String(localized: "Open Swaddle and save one diaper with both pee and poo, with Undo if needed.")) }
}
struct BottleLockScreenWidget: Widget {
    var body: some WidgetConfiguration { quickLogConfiguration(.bottle, name: String(localized: "Bottle"), description: String(localized: "Open a bottle with your previous amounts. Review the time and volume, then save.")) }
}

#Preview("Pee", as: .accessoryCircular) { PeeLockScreenWidget() } timeline: {
    QuickLogEntry(date: .now, canRecord: true, isPreview: true)
}
#Preview("Poo", as: .accessoryCircular) { PooLockScreenWidget() } timeline: {
    QuickLogEntry(date: .now, canRecord: true, isPreview: true)
}
#Preview("Both", as: .accessoryCircular) { BothLockScreenWidget() } timeline: {
    QuickLogEntry(date: .now, canRecord: true, isPreview: true)
}
#Preview("Bottle", as: .accessoryCircular) { BottleLockScreenWidget() } timeline: {
    QuickLogEntry(date: .now, canRecord: true, isPreview: true)
}
