import Foundation
import Testing
@testable import LittleLogCore

struct MultilingualInputTests {
    @Test(arguments: ["en_US", "es_ES", "ar_SA", "pt_BR", "fa_IR", "fr_FR", "ht_HT", "hi_IN", "ko_KR", "zh_CN", "so_SO", "fil_PH", "vi_VN", "ru_RU"])
    func editableQuantitiesRoundTripForEveryChecklistLanguage(localeID: String) {
        let locale = Locale(identifier: localeID)
        for value in ["73.93", "59.147059125", "14.78676478125", "0.25", "4.495", "0", "120"] {
            let amount = Decimal(string: value)!
            let editable = JSONLinesCareImport.number(amount, locale: locale)
            #expect(Decimal.input(editable, locale: locale) == amount)
        }
    }

    @Test func translatedChecklistLinksKeepTheCorrectAgeAndPublisher() {
        for language in CDCMilestoneLanguage.allCases {
            for skill in MilestoneCatalog.all {
                let url = language.sourceURL(for: skill)
                #expect(URL(string: url) != nil)
                if skill.motorWindow != nil {
                    #expect(url == skill.sourceURL)
                } else if language == .russian {
                    #expect(url == skill.sourceURL)
                    #expect(!url.contains(".pdf"))
                } else if language != .english && language != .spanish {
                    let index = MilestoneCatalog.checkpoints.firstIndex(of: skill.months!)!
                    #expect(url.hasSuffix("#page=\(index * 2 + 1)"))
                    #expect(url.contains("www.cdc.gov/act-early/media/pdfs/"))
                }
            }
        }
    }

    @Test func regionalAndTagalogAliasesResolveWithoutChangingDataIdentity() {
        #expect(CDCMilestoneLanguage.resolve("pt_BR") == .portuguese)
        #expect(CDCMilestoneLanguage.resolve("fr-CA") == .french)
        #expect(CDCMilestoneLanguage.resolve("tl-PH") == .tagalog)
        #expect(CDCMilestoneLanguage.resolve("fil_PH") == .tagalog)
        #expect(CDCMilestoneLanguage.resolve("zh-CN") == .chinese)
        #expect(CDCMilestoneLanguage.resolve("ru_RU") == .russian)
        #expect(CDCMilestoneLanguage.resolve("ar-SA").isRightToLeft)
        #expect(CDCMilestoneLanguage.resolve("fa-IR").isRightToLeft)
        #expect(!CDCMilestoneLanguage.resolve("hi-IN").isRightToLeft)
        #expect(CDCMilestoneLanguage.resolve("xx-YY") == .english)
    }
}
