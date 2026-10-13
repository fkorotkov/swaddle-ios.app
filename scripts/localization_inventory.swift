import Foundation
import SwiftParser
import SwiftSyntax

// Source-aware review inventory. It never changes user data, keys, symbols, or source code.
final class Strings: SyntaxVisitor {
    let path: String
    let converter: SourceLocationConverter
    var entries: [[String: Any]] = []
    init(path: String, tree: SourceFileSyntax) {
        self.path = path
        converter = SourceLocationConverter(fileName: path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }
    override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
        var cursor = node.parent
        var variables: [String] = [], calls: [String] = [], functions: [String] = [], types: [String] = []
        var conditionals: [String] = [], assignments: [String] = [], labels: [String] = []
        let argumentLabel = node.parent?.as(LabeledExprSyntax.self)?.label?.text ?? ""
        let directArgument = node.parent?.is(LabeledExprSyntax.self) ?? false
        var displayAlternative = false
        if let ternary = node.parent?.as(TernaryExprSyntax.self) {
            displayAlternative = ternary.thenExpression.id == node.id || ternary.elseExpression.id == node.id
        }
        if let ternary = node.parent?.as(UnresolvedTernaryExprSyntax.self) {
            displayAlternative = ternary.thenExpression.id == node.id
        }
        if let sequence = node.parent?.parent?.as(SequenceExprSyntax.self) {
            displayAlternative = sequence.elements.contains {
                $0.as(BinaryOperatorExprSyntax.self)?.operator.text == "??" || $0.is(UnresolvedTernaryExprSyntax.self)
            }
        }
        while let current = cursor {
            if let variable = current.as(VariableDeclSyntax.self) {
                variables += variable.bindings.map { $0.pattern.description.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            if let argument = current.as(LabeledExprSyntax.self), let label = argument.label { labels.append(label.text) }
            if let call = current.as(FunctionCallExprSyntax.self) {
                if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                    let prefix = member.base?.as(DeclReferenceExprSyntax.self)?.baseName.text ?? ""
                    calls.append(prefix + "." + member.declName.baseName.text)
                } else {
                    calls.append(call.calledExpression.description.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            if let sequence = current.as(SequenceExprSyntax.self) {
                let elements = Array(sequence.elements)
                if let index = elements.firstIndex(where: { $0.is(AssignmentExprSyntax.self) }) {
                    assignments.append(elements[..<index].map(\.description).joined().trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            if let function = current.as(FunctionDeclSyntax.self) { functions.append(function.name.text) }
            if let type = current.as(StructDeclSyntax.self) { types.append(type.name.text) }
            if let type = current.as(EnumDeclSyntax.self) { types.append(type.name.text) }
            if let clause = current.as(IfConfigClauseSyntax.self), let condition = clause.condition { conditionals.append(condition.description) }
            cursor = current.parent
        }
        let location = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        entries.append(["file": path, "line": location.line, "start": node.positionAfterSkippingLeadingTrivia.utf8Offset,
            "end": node.endPositionBeforeTrailingTrivia.utf8Offset, "literal": node.description.trimmingCharacters(in: .whitespacesAndNewlines),
            "variables": variables, "functions": functions, "calls": calls, "types": types, "conditionals": conditionals,
            "argumentLabel": argumentLabel, "directArgument": directArgument, "assignments": assignments, "labels": labels,
            "displayAlternative": displayAlternative])
        return .visitChildren
    }
}

var output: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    let tree = Parser.parse(source: try String(contentsOfFile: path, encoding: .utf8))
    let strings = Strings(path: path, tree: tree)
    strings.walk(tree)
    output += strings.entries
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]))
