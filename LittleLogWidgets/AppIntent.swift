import AppIntents
import WidgetKit
import Foundation

struct WidgetChild: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Child" }
    static var defaultQuery: WidgetChildQuery { WidgetChildQuery() }
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}
struct WidgetChildQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetChild] {
        children().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WidgetChild] { children() }
    func defaultResult() async -> WidgetChild? {
        let children = children()
        return children.count == 1 ? children.first : nil
    }
    private func children() -> [WidgetChild] {
        (WidgetCache.read()?.children ?? []).map { WidgetChild(id: "\($0.familyID.uuidString)/\($0.id.uuidString)", name: $0.name) }
    }
}
struct SelectChildIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Choose a child" }
    static var description: IntentDescription { "Keep this widget linked to one child in your family." }
    @Parameter(title: "Child") var child: WidgetChild?
}
struct SetWidgetVolumeUnitIntent: AppIntent {
    static var title: LocalizedStringResource { "Set widget volume units" }
    static var isDiscoverable: Bool { false }
    @Parameter(title: "Use ounces") var useOunces: Bool
    init() {}
    init(useOunces: Bool) { self.useOunces = useOunces }
    func perform() async throws -> some IntentResult {
        // Setting an explicit target makes retries idempotent.
        WidgetCache.setUnit(useOunces ? .oz : .ml)
        return .result()
    }
}
