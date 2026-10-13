import Foundation
import Testing
@testable import BabyActivityRecorder

struct MultilingualLocalizationTests {
    private static let locales = ["ar", "pt-BR", "fa", "fr", "ht", "hi", "ko", "zh-Hans", "so", "fil", "vi", "ru"]
    private static let bottles = ["ar": "رضّاعة", "pt-BR": "Mamadeira", "fa": "شیشه شیر", "fr": "Biberon",
                                  "ht": "Bibwon", "hi": "बोतल", "ko": "젖병", "zh-Hans": "奶瓶",
                                  "so": "Dhalo", "fil": "Bote", "vi": "Bình sữa", "ru": "Бутылочка"]

    private func bundle(_ language: String, in root: Bundle = .main) throws -> Bundle {
        let path = try #require(root.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test(arguments: locales)
    func everyNewLanguageIsBundledForLoggingAndMilestones(language: String) throws {
        let localized = try bundle(language)
        #expect(String(localized: "Bottle", bundle: localized) == Self.bottles[language])
        for key in ["Settings", "Pumping", "Milestones", "Custom", "Record a diaper"] {
            #expect(localized.localizedString(forKey: key, value: nil, table: nil) != key)
        }
        for skill in MilestoneCatalog.all {
            let title = localized.localizedString(forKey: skill.id, value: nil, table: "Milestones")
            #expect(title != skill.id)
            #expect(title != skill.title)
        }
    }

    @Test(arguments: locales)
    func widgetHasItsOwnTranslations(language: String) throws {
        let plugin = try #require(Bundle.main.builtInPlugInsURL)
        let extensionBundle = try #require(Bundle(url: plugin.appendingPathComponent("LittleLogWidgetsExtension.appex")))
        let localized = try bundle(language, in: extensionBundle)
        #expect(String(localized: "Bottle", bundle: localized) == Self.bottles[language])
        #expect(localized.localizedString(forKey: "Choose a child", value: nil, table: nil) != "Choose a child")
        for key in ["Care & quick log", "Family pumping",
                    "Last 24 hours of bottles, family pumping, and diapers, with Pee, Poo, Both, and Bottle actions."] {
            #expect(localized.localizedString(forKey: key, value: nil, table: nil) != key)
        }
    }

    @Test func publishedTitlesRetainCorrectSkillAndFrozenSource() throws {
        let arabic = try bundle("ar")
        #expect(arabic.localizedString(forKey: "cdc-6-laughs_id", value: nil, table: "Milestones") == "يضحك")
        let french = try bundle("fr")
        let kick = try #require(MilestoneCatalog.skills(at: 24).first { $0.title == "Kicks a ball" })
        #expect(french.localizedString(forKey: kick.id, value: nil, table: "Milestones") == "Donne un coup de pied dans un ballon")
        #expect(kick.title == "Kicks a ball")
        let persian = try bundle("fa")
        let calms = try #require(MilestoneCatalog.skill("cdc-2-calmsdown"))
        #expect(persian.localizedString(forKey: calms.id, value: nil, table: "Milestones") == "برطرف شدن ناراحتی در واکنش به صحبت کردن یا بغل کردن")
        #expect(calms.sourceVersion == "cdc-2026-10-10")
    }

    @Test(arguments: [1, 2, 5, 11, 21, 22, 25])
    func russianCompiledPluralsChooseTheCorrectEnding(count: Int) throws {
        let russian = try bundle("ru")
        let format = russian.localizedString(forKey: "%lld days", value: nil, table: nil)
        let actual = String(format: format, locale: Locale(identifier: "ru_RU"), count)
        let ending = [1, 21].contains(count) ? "день" : ([2, 22].contains(count) ? "дня" : "дней")
        #expect(actual == "\(count) \(ending)")
    }

    @Test(arguments: ["en_US", "es_ES", "ar_SA", "pt_BR", "fa_IR", "fr_FR", "ht_HT", "hi_IN", "ko_KR", "zh_CN", "so_SO", "fil_PH", "vi_VN", "ru_RU"])
    func localizedMeasurementsRetainExactValuesOnIOS(localeID: String) {
        let locale = Locale(identifier: localeID)
        for value in ["73.93", "59.147059125", "14.78676478125", "0.25", "4.495", "0", "120"] {
            let amount = Decimal(string: value)!
            let editable = JSONLinesCareImport.number(amount, locale: locale)
            #expect(Decimal.input(editable, locale: locale) == amount)
        }
    }
}
