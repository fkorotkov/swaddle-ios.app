import Foundation

nonisolated enum CaregiverSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case female, male
    var id: String { rawValue }
    var title: String { self == .female ? String(localized: "Female") : String(localized: "Male") }
}

enum CaregiverSexEdits {
    static func applying(to latest: Caregiver, baseline: Caregiver?, sex: CaregiverSex?) -> Caregiver {
        var person = latest
        if baseline == nil || sex != baseline?.sex { person.sex = sex }
        return person
    }
}
