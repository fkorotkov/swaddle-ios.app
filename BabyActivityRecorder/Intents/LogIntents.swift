import AppIntents
import Foundation

nonisolated extension VolumeUnit: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Volume unit" }
    static var caseDisplayRepresentations: [VolumeUnit: DisplayRepresentation] {
        [.ml: .init(title: "Milliliters", synonyms: ["mL", "millilitres"]), .oz: .init(title: "Ounces", synonyms: ["ounces", "oz"])]
    }
}
nonisolated extension BreastSide: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Breast side" }
    static var caseDisplayRepresentations: [BreastSide: DisplayRepresentation] { [.left: "Left", .right: "Right"] }
}

enum DiaperKind: String, AppEnum {
    case pee, poo, both
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Diaper contents" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.pee: .init(title: "Pee only", synonyms: ["Only pee", "Pee", "Wet diaper"]),
         .poo: .init(title: "Poo only", synonyms: ["Only poo", "Poo", "Poop"]),
         .both: .init(title: "Pee and poo", synonyms: ["Poo and pee", "Pee and poop", "Both", "Wet and dirty"])]
    }
}

struct ChildEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Child" }
    static var defaultQuery: ChildQuery { ChildQuery() }
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}
struct ChildQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [ChildEntity] { try all().filter { identifiers.contains($0.id) } }
    @MainActor func entities(matching string: String) async throws -> [ChildEntity] { try all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    @MainActor func suggestedEntities() async throws -> [ChildEntity] { try all() }
    @MainActor private func all() throws -> [ChildEntity] {
        let store = LogStore.shared; store.reload()
        guard store.isReady else { throw LogError.message("Your family is still loading.") }
        return store.snapshot.children.map { ChildEntity(id: $0.id, name: $0.name) }
    }
}

struct MotherEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Mother" }
    static var defaultQuery: MotherQuery { MotherQuery() }
    var id: UUID
    var name: String
    var displayRepresentation: DisplayRepresentation { .init(title: "\(name)") }
}
struct MotherQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [UUID]) async throws -> [MotherEntity] { all().filter { identifiers.contains($0.id) } }
    @MainActor func entities(matching string: String) async throws -> [MotherEntity] { all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    @MainActor func suggestedEntities() async throws -> [MotherEntity] { all() }
    @MainActor private func all() -> [MotherEntity] {
        LogStore.shared.reload()
        return LogStore.shared.snapshot.caregivers.filter(\.isMother).map { MotherEntity(id: $0.id, name: $0.name) }
    }
}

@MainActor
enum IntentResolution {
    static func child(_ entity: ChildEntity?, parameter: IntentParameter<ChildEntity?>) async throws -> ChildProfile {
        let store = LogStore.shared; store.reload()
        do { return try LogRules.child(entity?.id, in: store.snapshot, ready: store.isReady) }
        catch LogError.needsChild {
            let selected = try await parameter.requestDisambiguation(among: store.snapshot.children.map { ChildEntity(id: $0.id, name: $0.name) }, dialog: "Which child?")
            return try LogRules.child(selected.id, in: store.snapshot)
        }
    }
    static func mother(_ entity: MotherEntity?, parameter: IntentParameter<MotherEntity?>) async throws -> Caregiver {
        let store = LogStore.shared; store.reload()
        do { return try LogRules.mother(entity?.id, in: store.snapshot) }
        catch LogError.needsMother {
            let selected = try await parameter.requestDisambiguation(among: store.snapshot.caregivers.filter(\.isMother).map { MotherEntity(id: $0.id, name: $0.name) }, dialog: "Which mother?")
            return try LogRules.mother(selected.id, in: store.snapshot)
        }
    }
    static func record(child: ChildProfile, payload: ActivityPayload, date: Date, remember: Bool = false) throws {
        let store = LogStore.shared
        let activity = Activity(familyID: child.familyID, childID: child.id, occurredAt: date, authorID: store.caregiverID, source: "Siri / Shortcuts", payload: payload)
        try store.save(.activity(activity), rememberBottle: remember)
    }
}

struct RecordDiaperIntent: AppIntent {
    static var title: LocalizedStringResource { "Record a diaper" }
    static var description: IntentDescription { "Record pee, poo, or both. With one child, no name is needed." }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Child") var child: ChildEntity?
    @Parameter(title: "Contents") var contents: DiaperKind
    @Parameter(title: "Time") var time: Date?
    @Parameter(title: "Minutes ago", default: 0) var minutesAgo: Int
    static var parameterSummary: some ParameterSummary { Summary("Record \(\.$contents)") { \.$child; \.$time; \.$minutesAgo } }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let anchor = Date.now
        guard minutesAgo >= 0 else { throw LogError.message("Minutes ago can’t be negative.") }
        let date = time ?? anchor.addingTimeInterval(Double(-minutesAgo) * 60)
        let target = try await IntentResolution.child(child, parameter: $child)
        let diaper = Diaper(pee: contents != .poo, poo: contents != .pee)
        try IntentResolution.record(child: target, payload: .diaper(diaper), date: date)
        return .result(dialog: "Recorded \(diaper.title.lowercased()) for \(target.name) at \(date.formatted(date: .omitted, time: .shortened)).")
    }
}

enum BottleContents: String, AppEnum {
    case milk, formula, mixed
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Bottle contents" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] {
        [.milk: .init(title: "Breast milk", synonyms: ["Milk", "BM"]),
         .formula: "Formula", .mixed: .init(title: "Both", synonyms: ["Mixed", "Milk and formula"])]
    }
}

struct RecordBottleIntent: AppIntent {
    static var title: LocalizedStringResource { "Record a bottle" }
    static var description: IntentDescription { "Record a bottle of breast milk, formula, or both. Ask for missing amounts and units before saving." }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Child") var child: ChildEntity?
    @Parameter(title: "Milk amount") var milk: Double?
    @Parameter(title: "Formula amount") var formula: Double?
    @Parameter(title: "Bottle contents") var contents: BottleContents?
    @Parameter(title: "Unit", requestValueDialog: "Milliliters or ounces?") var unit: VolumeUnit
    @Parameter(title: "Time") var time: Date?
    @Parameter(title: "Minutes ago", default: 0) var minutesAgo: Int
    static var parameterSummary: some ParameterSummary { Summary("Record a bottle in \(\.$unit)") { \.$milk; \.$formula; \.$contents; \.$child; \.$time; \.$minutesAgo } }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let anchor = Date.now
        guard minutesAgo >= 0 else { throw LogError.message("Minutes ago can’t be negative.") }
        let date = time ?? anchor.addingTimeInterval(Double(-minutesAgo) * 60)
        let amounts = try await BottleVoiceFlow.amounts(milk: milk, formula: formula, contents: contents,
            askContents: { try await $contents.requestValue("Breast milk, formula, or both?") },
            askMilk: { try await $milk.requestValue("How much breast milk in \(unit.label)?") },
            askFormula: { try await $formula.requestValue("How much formula in \(unit.label)?") })
        let target = try await IntentResolution.child(child, parameter: $child)
        let bottle = Bottle(milkML: unit.toML(amounts.milk), formulaML: unit.toML(amounts.formula), unit: unit)
        try IntentResolution.record(child: target, payload: .bottle(bottle), date: date, remember: true)
        return .result(dialog: "Recorded \(unit.quantity(bottle.milkML)) milk and \(unit.quantity(bottle.formulaML)) formula for \(target.name) at \(date.formatted(date: .omitted, time: .shortened)).")
    }
}

struct RecordUsualBottleIntent: AppIntent {
    static var title: LocalizedStringResource { "Record the usual bottle" }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Child") var child: ChildEntity?
    @Parameter(title: "Time") var time: Date?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let date = time ?? .now
        let target = try await IntentResolution.child(child, parameter: $child)
        guard let bottle = LogStore.shared.previousBottle(childID: target.id) else { throw LogError.message("Record a bottle for this child first.") }
        try await requestConfirmation(dialog: "Record \(bottle.unit.quantity(bottle.milkML)) milk and \(bottle.unit.quantity(bottle.formulaML)) formula for \(target.name)?")
        try IntentResolution.record(child: target, payload: .bottle(bottle), date: date, remember: true)
        return .result(dialog: "Recorded the bottle for \(target.name).")
    }
}

struct RecordPumpingIntent: AppIntent {
    static var title: LocalizedStringResource { "Record pumping" }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Mother") var mother: MotherEntity?
    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Unit") var unit: VolumeUnit
    @Parameter(title: "Time") var time: Date?
    @Parameter(title: "Minutes ago", default: 0) var minutesAgo: Int
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount.isFinite, let entered = Decimal(string: String(amount)), minutesAgo >= 0 else { throw LogError.message("Check the amount and time.") }
        let date = time ?? Date.now.addingTimeInterval(Double(-minutesAgo) * 60)
        let target = try await IntentResolution.mother(mother, parameter: $mother)
        let store = LogStore.shared
        let ml = unit.toML(entered)
        let session = PumpSession(familyID: target.familyID, motherID: target.id, occurredAt: date,
                                  authorID: store.caregiverID, source: "Siri / Shortcuts", totalML: ml, unit: unit)
        try store.save(.pumping(session))
        if store.pumpingCelebration?.id == session.id {
            store.toast = "Pumping saved for \(target.name)"
            return .result(dialog: "Recorded \(unit.quantity(ml)) pumped for \(target.name). A new personal record.")
        }
        return .result(dialog: "Recorded \(unit.quantity(ml)) pumped for \(target.name).")
    }
}

enum NursingAction: String, AppEnum {
    case start, pause, resume, switchSide, finish
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Timer action" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] { [.start: "Start", .pause: "Pause", .resume: "Resume", .switchSide: "Switch side", .finish: "Finish"] }
}
struct BreastfeedingTimerIntent: AppIntent {
    static var title: LocalizedStringResource { "Breastfeeding timer" }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Child") var child: ChildEntity?
    @Parameter(title: "Action", default: .start) var action: NursingAction
    @Parameter(title: "Side") var side: BreastSide?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let store = LogStore.shared; store.reload()
        let active = store.snapshot.activities.filter { a in
            guard case .nursing(let n) = a.payload else { return false }
            return !n.finished && n.caregiverID == store.caregiverID && (child == nil || a.childID == child?.id)
        }
        let target: ChildProfile
        if action != .start && active.count == 1 { target = try LogRules.child(active[0].childID, in: store.snapshot) }
        else { target = try await IntentResolution.child(child, parameter: $child) }
        let matches = active.filter { $0.childID == target.id }
        if action == .start {
            guard matches.isEmpty else { throw LogError.message("A timer for this child is already active.") }
            var n = Nursing(caregiverID: store.caregiverID); n.start(side ?? .left, at: now)
            try IntentResolution.record(child: target, payload: .nursing(n), date: now)
        } else {
            guard matches.count == 1, var a = matches.first, case .nursing(var n) = a.payload else { throw LogError.message("Open Swaddle to choose among active sessions, or start a timer first.") }
            switch action {
            case .pause: n.pause(at: now)
            case .finish: n.pause(at: now); n.finished = true
            case .resume: n.resume(on: side, at: now)
            case .switchSide: n.switchSide(at: now)
            case .start: break
            }
            a.payload = .nursing(n)
            try store.save(.activity(a))
        }
        return .result(dialog: "Updated breastfeeding for \(target.name).")
    }
}

struct RecordBreastfeedingIntent: AppIntent {
    static var title: LocalizedStringResource { "Record breastfeeding" }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Child") var child: ChildEntity?
    @Parameter(title: "Left minutes", default: 0) var left: Double
    @Parameter(title: "Right minutes", default: 0) var right: Double
    @Parameter(title: "Finished at") var time: Date?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let end = time ?? .now
        guard left.isFinite, right.isFinite, left >= 0, right >= 0, left + right > 0 else { throw LogError.message("Enter a positive duration.") }
        let target = try await IntentResolution.child(child, parameter: $child)
        let start = end.addingTimeInterval(-(left + right) * 60)
        var nursing = Nursing(caregiverID: LogStore.shared.caregiverID)
        if left > 0 { nursing.segments.append(NursingSegment(side: .left, start: start, end: start.addingTimeInterval(left * 60))) }
        if right > 0 { nursing.segments.append(NursingSegment(side: .right, start: end.addingTimeInterval(-right * 60), end: end)) }
        nursing.finished = true
        try IntentResolution.record(child: target, payload: .nursing(nursing), date: start)
        return .result(dialog: "Recorded breastfeeding for \(target.name).")
    }
}

enum MeasurementKind: String, AppEnum {
    case weightKG, weightGrams, temperatureC, temperatureF
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Measurement" }
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] { [.weightKG: "Weight in kilograms", .weightGrams: "Weight in grams", .temperatureC: "Temperature in Celsius", .temperatureF: "Temperature in Fahrenheit"] }
}
struct RecordMeasurementIntent: AppIntent {
    static var title: LocalizedStringResource { "Record weight or temperature" }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Child") var child: ChildEntity?
    @Parameter(title: "Measurement") var measurement: MeasurementKind
    @Parameter(title: "Value") var value: Double
    @Parameter(title: "Time") var time: Date?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let date = time ?? .now
        guard value.isFinite, let amount = Decimal(string: String(value)) else { throw LogError.message("Enter a valid measurement.") }
        let target = try await IntentResolution.child(child, parameter: $child)
        let payload: ActivityPayload
        switch measurement {
        case .weightKG: payload = .weight(grams: amount * 1000, unit: "kg")
        case .weightGrams: payload = .weight(grams: amount, unit: "g")
        case .temperatureC: payload = .temperature(celsius: amount, unit: "°C", method: "")
        case .temperatureF: payload = .temperature(celsius: (amount - 32) * 5 / 9, unit: "°F", method: "")
        }
        try IntentResolution.record(child: target, payload: payload, date: date)
        return .result(dialog: "Recorded the measurement for \(target.name).")
    }
}
struct RecentActivityIntent: AppIntent {
    static var title: LocalizedStringResource { "Get last 24 hours" }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Child") var child: ChildEntity?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let child = try await IntentResolution.child(child, parameter: $child)
        let store = LogStore.shared
        let summary = ActivitySummary(activities: store.snapshot.activities, childID: child.id, start: now.addingTimeInterval(-86400), end: now)
        return .result(dialog: "For \(child.name) in the last 24 hours: \(summary.wet) wet and \(summary.soiled) soiled diapers across \(summary.changes) changes. \(store.volumeUnit.quantity(summary.milkML)) milk and \(store.volumeUnit.quantity(summary.formulaML)) formula recorded.\(summary.unknownML > 0 ? " Also \(store.volumeUnit.quantity(summary.unknownML)) with an unrecorded milk/formula split, included in total intake." : "")")
    }
}
struct PumpingHistoryIntent: AppIntent {
    static var title: LocalizedStringResource { "Get pumping totals" }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @Parameter(title: "Mother") var mother: MotherEntity?
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date.now
        let person = try await IntentResolution.mother(mother, parameter: $mother)
        let store = LogStore.shared
        let total = store.snapshot.pumps.filter { $0.motherID == person.id && $0.occurredAt > now.addingTimeInterval(-86400) && $0.occurredAt <= now }.reduce(Decimal(0)) { $0 + $1.totalML }
        return .result(dialog: "\(store.volumeUnit.quantity(total)) pumped for \(person.name) in the last 24 hours.")
    }
}
struct UndoLastLogIntent: AppIntent {
    static var title: LocalizedStringResource { "Undo my last log" }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = LogStore.shared; store.reload()
        let candidates = store.snapshot.records.filter { record in
            guard !record.isDeleted else { return false }
            switch record.revision.value {
            case .activity(let a): return a.authorID == store.caregiverID
            case .pumping(let p): return p.authorID == store.caregiverID
            default: return false
            }
        }.sorted { created($0) > created($1) }
        guard let record = candidates.first else { throw LogError.message("There are no entries of yours to undo.") }
        let description: String
        switch record.revision.value {
        case .activity(let a): description = "\(a.payload.kind.title) for \(store.snapshot.children.first { $0.id == a.childID }?.name ?? "child") at \(a.occurredAt.formatted())"
        case .pumping(let p): description = "Pumping for \(store.snapshot.caregiverName(p.motherID)) at \(p.occurredAt.formatted())"
        default: throw LogError.message("This entry can’t be undone.")
        }
        try await requestConfirmation(dialog: "Delete \(description)?")
        try store.delete(record)
        return .result(dialog: "Entry undone.")
    }
    private func created(_ record: ProjectedRecord) -> Date {
        switch record.revision.value { case .activity(let a): a.createdAt; case .pumping(let p): p.createdAt; default: .distantPast }
    }
}
struct LittleLogShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecordDiaperIntent(), phrases: [
            "Log a \(\.$contents) diaper in \(.applicationName)",
            "Record a \(\.$contents) diaper in \(.applicationName)",
            "Record a diaper in \(.applicationName)",
            "Log a diaper with \(.applicationName)",
            "Record \(\.$contents) in \(.applicationName)"
        ], shortTitle: "Record diaper", systemImageName: "drop.fill")
        AppShortcut(intent: RecordBottleIntent(), phrases: [
            "Record a bottle in \(.applicationName)",
            "Record the bottle in \(.applicationName)",
            "Log a bottle in \(.applicationName)",
            "Log a bottle with \(.applicationName)"
        ], shortTitle: "Record bottle", systemImageName: "waterbottle.fill")
        AppShortcut(intent: RecordPumpingIntent(), phrases: [
            "Log expressed milk in \(.applicationName)",
            "Log a pumping session in \(.applicationName)",
            "Record pumping in \(.applicationName)"
        ], shortTitle: "Record pumping", systemImageName: "drop.halffull")
        AppShortcut(intent: BreastfeedingTimerIntent(), phrases: ["Start breastfeeding in \(.applicationName)"], shortTitle: "Breastfeeding", systemImageName: "heart.fill")
        AppShortcut(intent: RecentActivityIntent(), phrases: ["Get recent activity in \(.applicationName)"], shortTitle: "Last 24 hours", systemImageName: "clock")
        AppShortcut(intent: GetFeedingIntakeIntent(), phrases: ["How much did my baby eat in \(.applicationName)", "How much did \(\.$child) eat in \(.applicationName)", "Get feeding totals in \(.applicationName)"], shortTitle: "Feeding totals", systemImageName: "waterbottle")
        AppShortcut(intent: GetLastFeedIntent(), phrases: ["When was the last feed in \(.applicationName)", "When did \(\.$child) last eat in \(.applicationName)"], shortTitle: "Last feed", systemImageName: "clock.arrow.circlepath")
        AppShortcut(intent: RecordUsualBottleIntent(), phrases: ["Record the usual bottle in \(.applicationName)"], shortTitle: "Usual bottle", systemImageName: "arrow.clockwise")
    }
}
