import Foundation
import Testing
@testable import LittleLogCore

struct SpanishNumberInputTests {
    @Test(arguments: ["es_ES", "es_MX", "en_US"])
    func importedDecimalsRoundTripWithoutChangingVolumes(localeID: String) {
        let locale = Locale(identifier: localeID)
        for source in ["73.93", "59.147059125", "14.78676478125", "0.25", "4.495"] {
            let number = Decimal(string: source)!
            let editable = JSONLinesCareImport.number(number, locale: locale)
            #expect(Decimal.input(editable, locale: locale) == number)
        }
    }

    @Test func spanishRegionAcceptsDecimalCommaAndKeepsExactWeight() {
        #expect(Decimal.input("4,495", locale: Locale(identifier: "es_ES")) == Decimal(string: "4.495"))
        #expect(Decimal.input("73,93", locale: Locale(identifier: "es_ES")) == Decimal(string: "73.93"))
        #expect(Decimal.input("73.93", locale: Locale(identifier: "es_MX")) == Decimal(string: "73.93"))
    }
}
