import Foundation

enum CareImportKind: String, CaseIterable, Identifiable, Sendable {
    case bottle, diaper, note
    var id: String { rawValue }
    var title: String { switch self { case .bottle: String(localized: "Bottle"); case .diaper: String(localized: "Diaper"); case .note: String(localized: "Care note") } }
}

enum CareLineHint: Sendable {
    case milk, formula, diaper(pee: Bool, poo: Bool), note
}

struct CareImportDraft: Identifiable, Equatable, Sendable {
    var id = UUID()
    var kind: CareImportKind
    var source: String
    var sourceLine: Int
    var block: Int
    var timestamp: Date?
    var timeWasExplicit = false
    var unit: VolumeUnit
    var milk = ""
    var formula = ""
    var unknown = ""
    var amountIssue: String?
    var reportedTotalML: Decimal?
    var timeZoneIdentifier: String?
    var isStructured = false
    var importIdentity: ImportIdentity?
    var importIssue: String?
    var pee = false
    var poo = false
    var note = ""
    var reviewReasons: [String] = []
    var included = true

    mutating func changeUnit(_ next: VolumeUnit) {
        guard next != unit else { return }
        for key in [\Self.milk, \Self.formula, \Self.unknown] where !self[keyPath: key].isEmpty {
            if let amount = Decimal.input(self[keyPath: key]) {
                self[keyPath: key] = next.fromML(unit.toML(amount)).formatted(.number.grouping(.never).precision(.fractionLength(0...12)))
            }
        }
        unit = next
    }
    mutating func setSplitUnknown(_ value: Bool) {
        if value {
            let total = reportedTotalML.map(unit.fromML) ?? ((Decimal.input(milk) ?? 0) + (Decimal.input(formula) ?? 0))
            unknown = total.formatted(.number.grouping(.never).precision(.fractionLength(0...12)))
        } else { unknown = "" }
        milk = ""; formula = ""; amountIssue = nil
    }

    func activity(child: ChildProfile, authorID: UUID, now: Date = .now) throws -> Activity {
        if let importIssue { throw LogError.message(importIssue) }
        guard let timestamp else { throw LogError.message(String(localized: "Choose a time for line \(sourceLine).")) }
        let payload: ActivityPayload
        switch kind {
        case .bottle:
            if let amountIssue { throw LogError.message(amountIssue) }
            guard let milk = milk.isEmpty ? 0 : Decimal.input(milk), let formula = formula.isEmpty ? 0 : Decimal.input(formula),
                  let unknown = unknown.isEmpty ? 0 : Decimal.input(unknown) else {
                throw LogError.message(String(localized: "Check the bottle amounts on line \(sourceLine)."))
            }
            let bottle = Bottle(milkML: unit.toML(milk), formulaML: unit.toML(formula), unit: unit, unclassifiedML: unknown == 0 ? nil : unit.toML(unknown))
            try bottle.validate()
            payload = .bottle(bottle)
        case .diaper:
            guard pee || poo else { throw LogError.message(String(localized: "Choose pee, poo, or both on line \(sourceLine).")) }
            payload = .diaper(Diaper(pee: pee, poo: poo))
        case .note:
            guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError.message(String(localized: "Enter the care note on line \(sourceLine).")) }
            payload = .careNote
        }
        try LogRules.past(timestamp, now: now)
        return Activity(id: id, familyID: child.familyID, childID: child.id, occurredAt: timestamp, timeZoneIdentifier: timeZoneIdentifier ?? TimeZone.current.identifier, authorID: authorID, source: "Text import", note: kind == .note ? note : source, payload: payload, importIdentity: importIdentity)
    }
    func sharesImportIdentity(with activity: Activity, child: ChildProfile) -> Bool {
        importIdentity != nil && importIdentity == activity.importIdentity && activity.childID == child.id && activity.familyID == child.familyID
    }
    static func excludingDuplicates(_ drafts: [Self], existing: [Activity], child: ChildProfile, authorID: UUID) -> [Self] {
        var seen = existing
        return drafts.map { draft in
            var row = draft
            if seen.contains(where: { row.sharesImportIdentity(with: $0, child: child) }) {
                row.included = false
                row.importIssue = String(localized: "This source and ID already exist for this child. Reimporting does not update an entry; edit the saved entry to make corrections.")
                row.reviewReasons.append(String(localized: "Already imported, or repeated earlier in this report. Excluded by source and ID; edit the saved entry to make corrections."))
            } else if seen.contains(where: { row.resembles($0, child: child, authorID: authorID) }) {
                row.included = false
                row.reviewReasons.append(String(localized: "A similar entry already exists or appears earlier in this report. Excluded unless you select it."))
            }
            if let activity = try? draft.activity(child: child, authorID: authorID) { seen.append(activity) }
            return row
        }
    }
    func resembles(_ activity: Activity, child: ChildProfile, authorID: UUID) -> Bool {
        guard let proposed = try? self.activity(child: child, authorID: authorID), activity.childID == child.id,
              abs(activity.occurredAt.timeIntervalSince(proposed.occurredAt)) < 60 else { return false }
        if case .bottle(let a) = activity.payload, case .bottle(let b) = proposed.payload {
            // Equivalent mL/oz exports can differ by a hundredth of a mL after rounding.
            let tolerance = Decimal(string: "0.01")!
            return abs(a.milkML - b.milkML) <= tolerance && abs(a.formulaML - b.formulaML) <= tolerance && abs(a.unknownML - b.unknownML) <= tolerance
        }
        guard activity.payload == proposed.payload else { return false }
        return kind != .note || activity.note == proposed.note
    }
}

nonisolated enum CareNoteParser {
    static let maximumCharacters = 50_000
    static let maximumLines = 500
    static let sample = """
    Pee
    Feed bm 11:28 pm 21/2
    He have a red mark on his cheek on both side think he’s getting baby acne

    Pee n poop
    Feed bm 2:36 am 3oz

    Pee n poop
    Feed bm 6 am 2 1/2 oz
    """

    static func parse(_ text: String, firstDay: Date, timeZone: TimeZone, defaultUnit: VolumeUnit, hints: [Int: CareLineHint] = [:]) throws -> [CareImportDraft] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LogError.message(String(localized: "Paste or type some care notes first.")) }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        let lines = normalized.components(separatedBy: .newlines)
        guard text.count <= maximumCharacters, lines.count <= maximumLines else { throw LogError.message(String(localized: "Import up to 50,000 characters or 500 lines at a time.")) }
        if JSONLinesCareImport.recognizes(normalized) { return try JSONLinesCareImport.parse(lines) }
        let reportZone = try StructuredCareImport.timeZone(in: lines) ?? timeZone
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = reportZone
        var day = calendar.startOfDay(for: firstDay)
        var previousMinute: Int?
        var block = 0
        let allUnits = Set(matches(#"(?<![a-z])(oz|ounces?|ml|milliliters?|millilitres?)\b"#, in: text.lowercased()).compactMap { unit($0.text) })
        let inferredUnit = allUnits.count == 1 ? allUnits.first! : defaultUnit
        var drafts: [CareImportDraft] = []
        for (index, original) in lines.enumerated() {
            let source = original.trimmingCharacters(in: .whitespacesAndNewlines)
            if source.isEmpty { block += 1; continue }
            if StructuredCareImport.isMetadata(source) { continue }
            if let draft = try StructuredCareImport.parse(source, line: index + 1, block: block, timeZone: reportZone) {
                drafts.append(draft)
                if let timestamp = draft.timestamp {
                    day = calendar.startOfDay(for: timestamp)
                    previousMinute = calendar.component(.hour, from: timestamp) * 60 + calendar.component(.minute, from: timestamp)
                }
                continue
            }
            var content = source.lowercased().replacingOccurrences(of: "\u{00a0}", with: " ")
            let explicitDay = matches(#"\b\d{4}-\d{2}-\d{2}\b"#, in: content).first
            if let explicitDay {
                guard let parsed = isoDay(explicitDay.text, calendar: calendar) else { throw LogError.message(String(localized: "Check the date on line \(index + 1).")) }
                day = parsed; previousMinute = nil
                content = content.replacingOccurrences(of: explicitDay.text, with: " ")
                if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            }
            let clock = clockTime(in: content)
            var timestamp: Date?
            var reasons: [String] = []
            if let clock {
                let minute = clock.hour * 60 + clock.minute
                if let previousMinute, minute < previousMinute {
                    if previousMinute - minute >= 720, explicitDay == nil {
                        day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
                        reasons.append("Rolled past midnight to the next day.")
                    } else { reasons.append("Time is earlier than the previous entry; check the date.") }
                }
                previousMinute = minute
                timestamp = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day)
                if let date = timestamp, calendar.component(.hour, from: date) != clock.hour || calendar.component(.minute, from: date) != clock.minute {
                    timestamp = nil; reasons.append("This local time doesn’t exist on the selected date. Choose a time.")
                }
                content = content.replacingOccurrences(of: clock.token, with: " ")
            }
            let negated = has(#"\b(no|not|never|without|didn't|didn’t|will|planned|planning|should|spilled|prepared|pumped|discarded|leftover)\b"#, content)
            let milk = has(#"\b(bm|ebm|breast\s*milk|expressed\s*milk|human\s*milk)\b"#, content)
            let formula = has(#"\bformula\b"#, content)
            let feeding = milk || formula || has(#"\b(feed|fed|bottle|feeding)\b"#, content)
            var pee = has(#"\b(pee|wee|wet|urine)\b"#, content)
            var poo = has(#"\b(poo|poop|stool|dirty)\b"#, content)
            var kind: CareImportKind = !negated && feeding ? .bottle : !negated && (pee || poo) ? .diaper : .note
            var isFormula = formula
            if kind == .note, !negated, let hint = hints[index + 1] {
                switch hint {
                case .milk: kind = .bottle; reasons.append("Interpreted as breast milk from the wording. Check the type and amount.")
                case .formula: kind = .bottle; isFormula = true; reasons.append("Interpreted as formula from the wording. Check the type and amount.")
                case .diaper(let wet, let soiled) where wet || soiled:
                    kind = .diaper; pee = wet; poo = soiled; reasons.append("Interpreted diaper contents from the wording. Please check.")
                default: break
                }
            }
            var draft = CareImportDraft(kind: kind, source: source, sourceLine: index + 1, block: block, timestamp: timestamp, timeWasExplicit: clock != nil, unit: inferredUnit, pee: pee, poo: poo, note: source, reviewReasons: reasons)
            draft.timeZoneIdentifier = reportZone.identifier
            if kind == .bottle {
                if feeding && !milk && !formula { draft.reviewReasons.append("Milk or formula wasn’t specified. Check the composition.") }
                let quantities = matches(#"(?<![\d/])(-?\d+\s+\d+/\d+|-?\d+[½¼¾]|-?\d+(?:[.,]\d+)?(?:/\d+)?|[½¼¾])\s*(oz|ounces?|ml|milliliters?|millilitres?)?(?![\p{L}\d/])"#, in: content)
                if quantities.count != 1 || (milk && formula) {
                    draft.reviewReasons.append("Enter the milk and formula amounts; the quantities are unclear.")
                } else if let quantity = quantities.first {
                    let rawNumber = quantity.groups[0]
                    if let amount = amount(rawNumber) {
                        let displayed = amount.value.formatted(.number.precision(.fractionLength(0...4)))
                        if isFormula { draft.formula = displayed } else { draft.milk = displayed }
                        if amount.compactFraction { draft.reviewReasons.append("Read “\(rawNumber)” as \(displayed). Confirm this fraction.") }
                    }
                    if let explicit = quantity.groups.count > 1 ? unit(quantity.groups[1]) : nil { draft.unit = explicit }
                    else { draft.reviewReasons.append("Unit missing; \(inferredUnit.label) is suggested. Confirm the unit.") }
                }
            }
            drafts.append(draft)
        }
        guard !drafts.isEmpty else { throw LogError.message(String(localized: "No activities found. Include a feed, diaper change, or care note below the report headings.")) }
        for index in drafts.indices where drafts[index].timestamp == nil && !drafts[index].timeWasExplicit {
            // The nearby time is only a review suggestion, never silently persisted.
            let nearby = drafts.filter { $0.block == drafts[index].block && $0.timestamp != nil }.min {
                abs($0.sourceLine - drafts[index].sourceLine) < abs($1.sourceLine - drafts[index].sourceLine)
            }
            if let nearby {
                drafts[index].timestamp = nearby.timestamp
                drafts[index].reviewReasons.append("No time given; suggested from line \(nearby.sourceLine). Check the time.")
            } else { drafts[index].reviewReasons.append("No time given. Choose a time before saving.") }
        }
        return drafts
    }

    static func amount(_ text: String) -> (value: Decimal, compactFraction: Bool)? {
        let clean = text.trimmingCharacters(in: .whitespaces)
        if clean.hasPrefix("-") {
            guard let positive = amount(String(clean.dropFirst())), positive.value >= 0 else { return nil }
            return (-positive.value, positive.compactFraction)
        }
        for (symbol, fraction) in [("½", Decimal(string: "0.5")!), ("¼", Decimal(string: "0.25")!), ("¾", Decimal(string: "0.75")!)] where clean.hasSuffix(symbol) {
            let whole = String(clean.dropLast()); guard let value = whole.isEmpty ? 0 : Decimal(string: whole) else { return nil }
            return (value + fraction, false)
        }
        let pieces = clean.split(separator: " ")
        if pieces.count == 2, let whole = Decimal(string: String(pieces[0])), let fraction = fraction(String(pieces[1])) { return (whole + fraction, false) }
        if let compact = matches(#"^(\d+)([13])/(2|4)$"#, in: clean).first,
           let whole = Decimal(string: compact.groups[0]), let numerator = Decimal(string: compact.groups[1]), let denominator = Decimal(string: compact.groups[2]) {
            return (whole + numerator / denominator, true)
        }
        if clean.contains("/") { return fraction(clean).map { ($0, false) } }
        return Decimal(string: clean.replacingOccurrences(of: ",", with: ".")).map { ($0, false) }
    }
    private static func fraction(_ text: String) -> Decimal? {
        let parts = text.split(separator: "/")
        guard parts.count == 2, let a = Decimal(string: String(parts[0])), let b = Decimal(string: String(parts[1])), b > 0 else { return nil }
        return a / b
    }
    private static func isoDay(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == parts[0] && roundTrip.month == parts[1] && roundTrip.day == parts[2] ? date : nil
    }
    private static func unit(_ text: String) -> VolumeUnit? {
        if text.hasPrefix("oz") || text.hasPrefix("ounce") { return .oz }
        if text.hasPrefix("ml") || text.hasPrefix("millil") { return .ml }
        return nil
    }
    private static func clockTime(in text: String) -> (hour: Int, minute: Int, token: String)? {
        if let match = matches(#"\b(1[0-2]|0?[1-9])(?::([0-5]\d))?\s*([ap])\.?m\.?\b"#, in: text).first,
           let hour = Int(match.groups[0]) {
            return (hour % 12 + (match.groups[2] == "p" ? 12 : 0), Int(match.groups[1]) ?? 0, match.text)
        }
        if let match = matches(#"\b([01]?\d|2[0-3]):([0-5]\d)\b"#, in: text).first,
           let hour = Int(match.groups[0]), let minute = Int(match.groups[1]) { return (hour, minute, match.text) }
        return nil
    }
    private struct Match { let text: String; let groups: [String] }
    private static func has(_ pattern: String, _ text: String) -> Bool { !matches(pattern, in: text).isEmpty }
    private static func matches(_ pattern: String, in text: String) -> [Match] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            func value(_ index: Int) -> String { Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
            return Match(text: value(0), groups: (1..<match.numberOfRanges).map(value))
        }
    }
}
