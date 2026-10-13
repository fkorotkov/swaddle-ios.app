import Foundation

/// CDC checklist languages plus Swaddle's Russian translation. Keep language
/// identity separate from a family's reporting time zone and stored skill IDs.
enum CDCMilestoneLanguage: String, CaseIterable, Sendable {
    case english = "en", spanish = "es", arabic = "ar", portuguese = "pt-BR"
    case persian = "fa", french = "fr", haitianCreole = "ht", hindi = "hi"
    case korean = "ko", chinese = "zh-Hans", somali = "so", tagalog = "fil", vietnamese = "vi"
    case russian = "ru"

    static func resolve(_ identifier: String) -> Self {
        let language = identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-").first
        switch language {
        case "es": return .spanish
        case "ar": return .arabic
        case "pt": return .portuguese
        case "fa": return .persian
        case "fr": return .french
        case "ht": return .haitianCreole
        case "hi": return .hindi
        case "ko": return .korean
        case "zh": return .chinese
        case "so": return .somali
        case "fil", "tl": return .tagalog
        case "vi": return .vietnamese
        case "ru": return .russian
        default: return .english
        }
    }

    var isRightToLeft: Bool { self == .arabic || self == .persian }

    var checklistURL: String {
        let base = "https://www.cdc.gov/act-early/media/pdfs/"
        switch self {
        case .english, .russian: return "https://www.cdc.gov/act-early/milestones/"
        case .spanish: return "https://www.cdc.gov/act-early/es/milestones/"
        case .arabic: return base + "2025/11/cdc-milestone-checklists-ltsae-arabic.pdf"
        case .portuguese: return base + "2025/10/cdc-milestone-checklists-ltsae-brazilian-portuguese-508.pdf"
        case .persian: return base + "2025/11/cdc-milestone-checklists-ltsae-farsi.pdf"
        case .french: return base + "2025/10/cdc-milestone-checklists-ltsae-french-508.pdf"
        case .haitianCreole: return base + "cdc-milestone-checklists-ltsae-haitian-creole-508.pdf?123"
        case .hindi: return base + "2025/11/cdc-milestone-checklists-ltsae-hindi.pdf"
        case .korean: return base + "2025/10/cdc-milestone-checklists-ltsae-korean.pdf"
        case .chinese: return base + "2025/11/cdc-milestone-checklists-ltsae-chinese.pdf"
        case .somali: return base + "2025/10/cdc-milestone-checklists-ltsae-somali-508.pdf"
        case .tagalog: return base + "2025/07/Tagalog-Milestone-Checklist-with-Tips-1.pdf"
        case .vietnamese: return base + "2025/11/cdc-milestone-checklists-ltsae-vietnamese.pdf"
        }
    }

    func sourceURL(for skill: MilestoneSkill) -> String {
        guard skill.motorWindow == nil else { return skill.sourceURL }
        if self == .english || self == .russian { return skill.sourceURL }
        if self == .spanish {
            return skill.sourceURL.replacingOccurrences(of: "/act-early/milestones/", with: "/act-early/es/milestones/")
        }
        guard let months = skill.months, let index = MilestoneCatalog.checkpoints.firstIndex(of: months) else { return checklistURL }
        return checklistURL + "#page=\(index * 2 + 1)"
    }
}
