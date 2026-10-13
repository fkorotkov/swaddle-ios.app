import Foundation

@MainActor
enum BottleVoiceFlow {
    /// Ask only for genuinely missing values. Explicit amounts never use remembered defaults.
    static func amounts(milk: Double?, formula: Double?, contents: BottleContents?,
                        askContents: () async throws -> BottleContents,
                        askMilk: () async throws -> Double,
                        askFormula: () async throws -> Double) async throws -> (milk: Decimal, formula: Decimal) {
        var milk = milk, formula = formula, choice = contents
        if milk == nil && formula == nil && choice == nil { choice = try await askContents() }
        if let choice {
            if choice == .milk && (formula ?? 0) != 0 || choice == .formula && (milk ?? 0) != 0 {
                throw LogError.message("The bottle contents and amounts don’t agree. Please try again with breast milk, formula, or both.")
            }
            if choice != .formula && milk == nil { milk = try await askMilk() }
            if choice != .milk && formula == nil { formula = try await askFormula() }
        }
        guard (milk ?? 0).isFinite, (formula ?? 0).isFinite,
              let milkAmount = Decimal(string: String(milk ?? 0)),
              let formulaAmount = Decimal(string: String(formula ?? 0)) else { throw LogError.message("Enter valid amounts.") }
        try LogRules.volumes([milkAmount, formulaAmount])
        return (milkAmount, formulaAmount)
    }
}
