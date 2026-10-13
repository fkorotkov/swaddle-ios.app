import Foundation

/// Keeps exact quantities separate from the rounded text shown in either unit.
struct VolumeDraft {
    enum Component { case first, second }

    var unit: VolumeUnit
    var firstML: Decimal?
    var secondML: Decimal?
    var firstText: String
    var secondText: String

    init(unit: VolumeUnit, firstML: Decimal? = nil, secondML: Decimal? = nil) {
        self.unit = unit; self.firstML = firstML; self.secondML = secondML
        firstText = firstML.map { unit.string($0) } ?? ""
        secondText = secondML.map { unit.string($0) } ?? ""
    }

    var step: Decimal { unit == .oz ? Decimal(string: "0.25")! : 10 }
    var stepLabel: String { "\(step.formatted()) \(unit.label)" }
    var total: Decimal { (firstML ?? 0) + (secondML ?? 0) }

    func text(for component: Component) -> String { component == .first ? firstText : secondText }
    func amount(for component: Component) -> Decimal? { component == .first ? firstML : secondML }

    mutating func setText(_ text: String, for component: Component) {
        let ml = text.isEmpty ? 0 : Decimal.input(text).map(unit.toML)
        if component == .first { firstText = text; firstML = ml }
        else { secondText = text; secondML = ml }
    }
    mutating func setFirst(_ value: String) { setText(value, for: .first) }
    mutating func setSecond(_ value: String) { setText(value, for: .second) }

    func canAdjust(_ direction: Int, component: Component) -> Bool {
        guard let ml = amount(for: component) ?? (text(for: component).isEmpty ? 0 : nil),
              !ml.isNaN, ml >= 0 else { return false }
        return direction > 0 || ml > 0
    }

    mutating func adjust(_ direction: Int, component: Component) {
        guard canAdjust(direction, component: component) else { return }
        let delta = unit.toML(step) * Decimal(direction)
        let ml = max(0, (amount(for: component) ?? 0) + delta)
        // Never round-trip the display string: + then − must restore the exact amount.
        if component == .first { firstML = ml; firstText = unit.string(ml) }
        else { secondML = ml; secondText = unit.string(ml) }
    }

    mutating func changeUnit(_ value: VolumeUnit) {
        guard unit != value else { return }
        unit = value
        if let firstML { firstText = value.string(firstML) }
        if let secondML { secondText = value.string(secondML) }
    }

    func validated() throws -> (Decimal, Decimal) {
        guard let first = firstML ?? (firstText.isEmpty ? 0 : nil),
              let second = secondML ?? (secondText.isEmpty ? 0 : nil) else {
            throw LogError.message(String(localized: "Enter a valid number for each amount."))
        }
        try LogRules.volumes([first, second])
        return (first, second)
    }
}

/// Only volume is reused. A new session must get its own time, notes, and identity.
struct PumpVolumePreset {
    let session: PumpSession

    var split: Bool {
        guard let left = session.leftML, let right = session.rightML,
              !left.isNaN, !right.isNaN, left >= 0, right >= 0 else { return false }
        return left + right == session.totalML
    }

    func draft(unit: VolumeUnit) -> VolumeDraft {
        VolumeDraft(unit: unit, firstML: split ? session.leftML : session.totalML,
                    secondML: split ? session.rightML : nil)
    }

    static func latest(for caregiverID: UUID?, in snapshot: FamilySnapshot, now: Date = .now) -> Self? {
        guard let caregiverID, let family = snapshot.family,
              snapshot.caregivers.contains(where: { $0.id == caregiverID && $0.familyID == family.id && $0.isMother }) else { return nil }
        let sessions = snapshot.pumps.filter { session in
            guard snapshot.record(session.id)?.hasConflict == false,
                  session.familyID == family.id, session.motherID == caregiverID,
                session.occurredAt <= now, !session.totalML.isNaN, session.totalML > 0
            else { return false }
            return true
        }
        let latest = sessions.max {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        return latest.map { Self(session: $0) }
    }
}
