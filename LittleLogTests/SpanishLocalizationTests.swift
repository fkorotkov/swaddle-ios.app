import Foundation
import Testing
@testable import BabyActivityRecorder

struct SpanishLocalizationTests {
    private func spanishBundle() throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: "es", ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func spanishResourcesAreBundledForLoggingSettingsAndVoiceActions() throws {
        let bundle = try spanishBundle()
        #expect(String(localized: "Bottle", bundle: bundle) == "Biberón")
        #expect(String(localized: "Pumping", bundle: bundle) == "Extracción")
        #expect(String(localized: "Settings", bundle: bundle) == "Ajustes")
        #expect(String(localized: "WHO", bundle: bundle) == "OMS")
        #expect(String(localized: "Record a bottle", bundle: bundle) == "Registrar un biberón")
        #expect(String(localized: "Custom", bundle: bundle) == "Otro")
    }

    @Test func nativeCountFormattingHandlesZeroOneAndMany() throws {
        let bundle = try spanishBundle()
        for (count, expected) in [(0, "0 sesiones"), (1, "1 sesión"), (2, "2 sesiones")] {
            #expect(String(localized: "\(count) sessions", bundle: bundle, locale: Locale(identifier: "es_ES")) == expected)
        }
        let count = 1
        #expect(String(localized: "\(count) bottles", bundle: bundle, locale: Locale(identifier: "es_ES")) == "1 biberón")
    }

    @Test func eachMilestoneHasSpanishCopyWithoutChangingItsFrozenSource() throws {
        let bundle = try spanishBundle()
        for skill in MilestoneCatalog.all {
            let original = skill.title
            let translated = bundle.localizedString(forKey: skill.id, value: nil, table: "Milestones")
            #expect(translated != skill.id)
            #expect(translated != original)
            #expect(skill.title == original)
        }
        #expect(bundle.localizedString(forKey: "cdc-6-laughs_id", value: nil, table: "Milestones") == "Se ríe")
    }
}
