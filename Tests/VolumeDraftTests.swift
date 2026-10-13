import Foundation
import Testing
@testable import LittleLogCore

struct VolumeDraftTests {
    @Test func quarterOunceAdjustmentsKeepTheOtherIngredientAndExactAmount() throws {
        let milk = VolumeUnit.oz.toML(3)
        var draft = VolumeDraft(unit: .oz, firstML: milk, secondML: VolumeUnit.oz.toML(1))
        draft.adjust(1, component: .first)
        let (adjusted, formula) = try draft.validated()
        #expect(adjusted == Decimal(string: "97.5"))
        #expect(formula == VolumeUnit.oz.toML(1))
        draft.adjust(-1, component: .first)
        #expect(draft.firstML == milk)
    }

    @Test func alternatingUnitsAndStepsNeverRoundTheUnderlyingValue() {
        var draft = VolumeDraft(unit: .ml, firstML: 90, secondML: 30)
        for _ in 0..<20 {
            draft.changeUnit(.oz)
            draft.adjust(1, component: .first)
            draft.adjust(-1, component: .first)
            draft.changeUnit(.ml)
            draft.adjust(1, component: .second)
            #expect(draft.secondML == 40)
            draft.adjust(-1, component: .second)
        }
        #expect(draft.firstML == 90 && draft.secondML == 30)
    }

    @Test func emptyAmountsCanIncreaseAndDecrementsStopAtZero() throws {
        var draft = VolumeDraft(unit: .ml)
        #expect(!draft.canAdjust(-1, component: .first))
        draft.adjust(1, component: .first)
        #expect(try draft.validated().0 == 10)
        draft.setFirst("7")
        draft.adjust(-1, component: .first)
        draft.adjust(-1, component: .first)
        #expect(draft.firstML == 0 && !draft.canAdjust(-1, component: .first))
        #expect(throws: LogError.self) { try draft.validated() }
    }

    @Test func invalidTextIsNotSilentlyReplacedByAnAdjustment() {
        var draft = VolumeDraft(unit: .oz, secondML: 30)
        draft.setFirst("invalid")
        draft.adjust(1, component: .first)
        #expect(draft.firstText == "invalid" && draft.firstML == nil)
        #expect(!draft.canAdjust(1, component: .first))
        #expect(throws: LogError.self) { try draft.validated() }
    }
    @Test func unitSwitchingUsesThirtyMLAndUnitSpecificSteps() throws {
        var draft = VolumeDraft(unit: .ml, firstML: 90, secondML: 30)
        draft.changeUnit(.oz)
        #expect(draft.firstText == "3" && draft.secondText == "1")
        #expect(draft.step == Decimal(string: "0.25"))
        draft.adjust(1, component: .first)
        draft.changeUnit(.ml)
        #expect(draft.firstML == Decimal(string: "97.5") && draft.secondML == 30)
        #expect(draft.step == 10)
        draft.adjust(1, component: .first)
        #expect(try draft.validated().0 == Decimal(string: "107.5"))
        draft.changeUnit(.oz)
        draft.setFirst("3.25")
        #expect(try draft.validated().0 == Decimal(string: "97.5"))
    }
    @Test func legacyExactVolumesSurviveUnitSwitchesAndAdjustments() throws {
        let legacyMilk = Decimal(string: "88.7205886875")!
        let legacyFormula = Decimal(string: "14.78676478125")!
        var draft = VolumeDraft(unit: .ml, firstML: legacyMilk, secondML: legacyFormula)
        for _ in 0..<20 {
            draft.changeUnit(.oz)
            draft.adjust(1, component: .first)
            draft.adjust(-1, component: .first)
            draft.changeUnit(.ml)
        }
        let (milk, formula) = try draft.validated()
        #expect(milk == legacyMilk && formula == legacyFormula)
    }
}
