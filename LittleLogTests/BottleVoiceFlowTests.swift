import Foundation
import Testing
@testable import BabyActivityRecorder

@MainActor
struct BottleVoiceFlowTests {
    enum UnexpectedPrompt: Error { case asked }
    @Test func formulaOnlyAsksForFormulaWithoutInventingMilk() async throws {
        var prompts: [String] = []
        let amounts = try await BottleVoiceFlow.amounts(milk: nil, formula: nil, contents: nil,
            askContents: { prompts.append("contents"); return .formula },
            askMilk: { throw UnexpectedPrompt.asked },
            askFormula: { prompts.append("formula"); return 130 })
        #expect(prompts == ["contents", "formula"])
        #expect(amounts.milk == 0 && amounts.formula == 130)
    }
    @Test func explicitValuesRemainCompatibleAndMixedOnlyAsksForMissingPart() async throws {
        let milkOnly = try await BottleVoiceFlow.amounts(milk: 3, formula: nil, contents: nil,
            askContents: { throw UnexpectedPrompt.asked }, askMilk: { throw UnexpectedPrompt.asked }, askFormula: { throw UnexpectedPrompt.asked })
        #expect(milkOnly.milk == 3 && milkOnly.formula == 0)
        let mixed = try await BottleVoiceFlow.amounts(milk: 2, formula: nil, contents: .mixed,
            askContents: { throw UnexpectedPrompt.asked }, askMilk: { throw UnexpectedPrompt.asked }, askFormula: { 0.5 })
        #expect(mixed.milk == 2 && mixed.formula == Decimal(string: "0.5"))
        #expect(VolumeUnit.oz.toML(mixed.milk + mixed.formula) == 75)
    }
    @Test func invalidAmountsContradictoryContentsAndCancelledDialogueFail() async {
        for (milk, formula, contents) in [(0.0, 0.0, BottleContents.mixed), (-1, 3, .mixed), (.infinity, 0, .milk), (3, 1, .milk), (3, 0, .formula)] {
            await #expect(throws: LogError.self) {
                try await BottleVoiceFlow.amounts(milk: milk, formula: formula, contents: contents,
                    askContents: { throw UnexpectedPrompt.asked }, askMilk: { throw UnexpectedPrompt.asked }, askFormula: { throw UnexpectedPrompt.asked })
            }
        }
        await #expect(throws: CancellationError.self) {
            try await BottleVoiceFlow.amounts(milk: nil, formula: nil, contents: nil,
                askContents: { throw CancellationError() }, askMilk: { throw UnexpectedPrompt.asked }, askFormula: { throw UnexpectedPrompt.asked })
        }
    }
}
