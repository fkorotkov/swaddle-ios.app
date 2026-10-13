import Foundation

/// Reads explicit export columns before considering free-form prose. Notes remain source text;
/// their incidental numbers, symptoms, and diaper mentions never create additional events.
nonisolated enum StructuredCareImport {
    // External exports historically use exact US fluid ounces. Keep that source
    // convention separate from Swaddle's 30 mL entry/display convenience.
    private static let millilitersPerUSFluidOunce = Decimal(string: "29.5735295625")!
    private static let number = #"(-?\d+\s+\d+/\d+|-?\d+[½¼¾]|-?\d+(?:[.,]\d+)?(?:/\d+)?|[½¼¾])"#
    private static let units = #"(ml|milliliters?|millilitres?|oz|ounces?)\b"#

    static func timeZone(in lines: [String]) throws -> TimeZone? {
        var result: TimeZone?
        for line in lines {
            guard let match = captures(#"^\s*Timezone:\s*([^\s.]+)"#, line).first else { continue }
            guard let zone = TimeZone(identifier: match[0]) else {
                throw LogError.message(String(localized: "Check the report’s time zone: \(match[0]). Use a name such as America/New_York."))
            }
            guard result == nil || result == zone else { throw LogError.message(String(localized: "The report has conflicting time zones. Import each time zone separately.")) }
            result = zone
        }
        return result
    }

    static func isMetadata(_ source: String) -> Bool {
        let text = source.lowercased()
        return text.hasPrefix("timezone:") || text.hasPrefix("entries:") ||
            text == "little days — complete feeding log" ||
            text.hasPrefix("amounts below are rounded") || text.hasPrefix("two components marked unknown") ||
            text.hasPrefix("bm = breast milk.") || text.hasPrefix("all feeds are bottles.") ||
            text.hasPrefix("volumes in ml rounded")
    }

    static func parse(_ source: String, line: Int, block: Int, timeZone: TimeZone) throws -> CareImportDraft? {
        let columns = source.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard columns.count >= 3, !captures(#"^\d{4}-\d{2}-\d{2}[ T]"#, columns[0]).isEmpty else { return nil }
        let fullExport = columns[1].lowercased() == "bottle feed"
        let typeIndex = fullExport ? 2 : 1
        guard columns.count > typeIndex + 1 else { throw LogError.message(String(localized: "A bottle total is missing on line \(line).")) }
        let type = columns[typeIndex].lowercased()
        let mixed = ["mixed", "mixed bm/formula", "mixed milk/formula"].contains(type)
        let milk = ["bm", "ebm", "breast milk", "breast-milk", "milk"].contains(type)
        let formula = type == "formula"
        guard mixed || milk || formula else { return nil }
        let timestamp = try date(columns[0], timeZone: timeZone, line: line)
        var draft = CareImportDraft(kind: .bottle, source: source, sourceLine: line, block: block,
                                    timestamp: timestamp, timeWasExplicit: true, unit: .ml,
                                    timeZoneIdentifier: timeZone.identifier, isStructured: true, note: source)
        let totalColumn = columns[typeIndex + 1].replacingOccurrences(of: #"^Total:\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard let total = quantity(totalColumn) else {
            draft.amountIssue = "The bottle total could not be read. Enter the amounts from the original note."
            return draft
        }
        draft.reportedTotalML = total.ml
        if let reason = total.reviewReason { draft.reviewReasons.append(reason) }
        let notes = columns.dropFirst(typeIndex + 2).joined(separator: " | ")
        if notes.range(of: #"(report time|exact (event )?time (not specified|unspecified))"#, options: [.regularExpression, .caseInsensitive]) != nil {
            draft.reviewReasons.append("Report time used; the exact feeding time wasn’t recorded.")
        }
        if mixed {
            let milkPart = component(#"(?:breast[ -]*milk|bm|ebm)"#, in: notes)
            let formulaPart = component("formula", in: notes)
            for reason in [milkPart?.reviewReason, formulaPart?.reviewReason].compactMap({ $0 }) where !draft.reviewReasons.contains(reason) {
                draft.reviewReasons.append(reason)
            }
            switch (milkPart, formulaPart) {
            case (.some(let a), .some(let b)):
                draft.milk = string(a.ml); draft.formula = string(b.ml)
                if abs(a.ml + b.ml - total.ml) > total.rounding + a.rounding + b.rounding + Decimal(string: "0.000001")! {
                    draft.amountIssue = "The milk and formula amounts don’t match the stated total of \(VolumeUnit.ml.quantity(total.ml)). Check and confirm the amounts."
                }
            case (nil, nil):
                draft.unknown = string(total.ml)
                draft.reviewReasons.append("Split not recorded. This volume counts toward total intake, separately from milk and formula.")
            default:
                draft.milk = milkPart.map { string($0.ml) } ?? ""
                draft.formula = formulaPart.map { string($0.ml) } ?? ""
                draft.amountIssue = "Only one part of this mixed bottle was recorded. Enter both amounts, or keep the total with an unknown split."
            }
        } else {
            // The explicit total column wins over repeated or historical quantities in notes.
            if milk { draft.milk = string(total.ml) } else { draft.formula = string(total.ml) }
        }
        return draft
    }

    private struct Quantity {
        var ml: Decimal
        var rounding: Decimal
        var reviewReason: String?
    }
    private static func quantity(_ text: String) -> Quantity? {
        guard let match = captures("^\\s*" + number + "\\s*" + units, text).first,
              let amount = CareNoteParser.amount(match[0]) else { return nil }
        let unit: VolumeUnit = match[1].lowercased().hasPrefix("m") ? .ml : .oz
        // Decimal mL values in exports are rounded. Whole values and ounce measures are exact inputs.
        let fractional = match[0].replacingOccurrences(of: ",", with: ".").split(separator: ".").dropFirst().first
        let rounding = unit == .ml && fractional != nil ? Decimal(sign: .plus, exponent: -fractional!.count, significand: Decimal(string: "0.5")!) : 0
        let reason = amount.compactFraction ? String(localized: "Read “\(match[0])” as \(string(amount.value)) \(unit.label). Confirm this fraction.") : nil
        let ml = unit == .ml ? amount.value : amount.value * millilitersPerUSFluidOunce
        return Quantity(ml: ml, rounding: rounding, reviewReason: reason)
    }
    private static func component(_ label: String, in text: String) -> Quantity? {
        guard let match = captures("\\b" + label + "\\s*:?\\s*(" + number + "\\s*" + units + ")", text).first else { return nil }
        return quantity(match[0])
    }
    private static func string(_ value: Decimal) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...12)))
    }

    static func date(_ text: String, timeZone: TimeZone, line: Int) throws -> Date {
        let invalid = LogError.message(String(localized: "Check the date, time, and UTC offset on line \(line)."))
        if text.contains("T"), text.hasSuffix("Z") || !captures(#"[+-]\d{2}:\d{2}$"#, text).isEmpty {
            guard let parts = captures(#"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|([+-])(\d{2}):(\d{2}))$"#, text).first else { throw invalid }
            let hour = Int(parts[8]) ?? 0, minute = Int(parts[9]) ?? 0
            guard hour <= 23 && minute <= 59 else { throw invalid }
            let offset = (hour * 3600 + minute * 60) * (parts[7] == "-" ? -1 : 1)
            var calendar = Calendar(identifier: .gregorian)
            guard let offsetZone = TimeZone(secondsFromGMT: offset) else { throw invalid }
            calendar.timeZone = offsetZone
            let formatter = ISO8601DateFormatter()
            if text.contains(".") { formatter.formatOptions.insert(.withFractionalSeconds) }
            guard let date = formatter.date(from: text) else { throw invalid }
            let check = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            guard [check.year, check.month, check.day, check.hour, check.minute, check.second] == parts.prefix(6).map({ Int($0) }) else { throw invalid }
            return date
        }
        guard let parts = captures(#"^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?$"#, text).first else { throw invalid }
        let values = parts.map { Int($0) ?? 0 }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let components = DateComponents(year: values[0], month: values[1], day: values[2], hour: values[3], minute: values[4], second: values[5])
        guard let date = calendar.date(from: components) else { throw invalid }
        let check = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard check == components else { throw invalid }
        return date
    }

    private static func captures(_ pattern: String, _ text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { match in
            (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
        }
    }
}
