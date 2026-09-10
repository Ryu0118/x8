/// Parses the POSIX-style scalar expressions supported by X8 configuration.
///
/// This type recognizes syntax only. It does not read environment values,
/// mutate assignments, execute commands, or perform pattern matching; those
/// responsibilities belong to `ScalarParameterExpander` and
/// `ShellPatternMatcher`.
enum ScalarParameterSyntax {
    enum BracedExpression {
        case length(String)
        case value(String)
        case pattern(name: String, pattern: String, prefix: Bool, longest: Bool)
        case conditional(name: String, operation: ConditionalOperation, word: String)
    }

    enum ConditionalOperation {
        case defaultValue(requiresNonEmpty: Bool)
        case assignValue(requiresNonEmpty: Bool)
        case requiredValue(requiresNonEmpty: Bool)
        case alternative(requiresNonEmpty: Bool)

        init(symbol: Character, hasColon: Bool) throws {
            let requiresNonEmpty = hasColon
            switch symbol {
            case "-": self = .defaultValue(requiresNonEmpty: requiresNonEmpty)
            case "=": self = .assignValue(requiresNonEmpty: requiresNonEmpty)
            case "?": self = .requiredValue(requiresNonEmpty: requiresNonEmpty)
            case "+": self = .alternative(requiresNonEmpty: requiresNonEmpty)
            default: throw X8ConfigurationResolutionError.unsupportedExpansion
            }
        }

        var requiresNonEmpty: Bool {
            switch self {
            case let .defaultValue(requiresNonEmpty),
                 let .assignValue(requiresNonEmpty),
                 let .requiredValue(requiresNonEmpty),
                 let .alternative(requiresNonEmpty):
                requiresNonEmpty
            }
        }
    }

    static func parseBraced(_ expression: String) throws -> BracedExpression {
        if expression.first == "#" {
            return try parseLengthExpression(expression)
        }

        let nameEnd = expression.firstIndex(where: { !isNameCharacter($0) })
            ?? expression.endIndex
        let name = String(expression[..<nameEnd])
        guard isName(name) else {
            throw X8ConfigurationResolutionError.unsupportedExpansion
        }
        guard nameEnd < expression.endIndex else { return .value(name) }

        // A colon changes the unset test into an unset-or-empty test.
        let hasColon = expression[nameEnd] == ":"
        let symbolStart = hasColon ? expression.index(after: nameEnd) : nameEnd
        guard symbolStart < expression.endIndex else {
            throw X8ConfigurationResolutionError.unsupportedExpansion
        }
        let symbol = expression[symbolStart]

        if symbol == "#" || symbol == "%" {
            let isLongest = expression.index(after: symbolStart) < expression.endIndex
                && expression[expression.index(after: symbolStart)] == symbol
            let patternStart = expression.index(symbolStart, offsetBy: isLongest ? 2 : 1)
            return .pattern(
                name: name,
                pattern: String(expression[patternStart...]),
                prefix: symbol == "#",
                longest: isLongest
            )
        }

        let wordStart = expression.index(after: symbolStart)
        let operation = try ConditionalOperation(symbol: symbol, hasColon: hasColon)
        return .conditional(
            name: name,
            operation: operation,
            word: String(expression[wordStart...])
        )
    }

    static func closingBrace(in value: String, after opening: String.Index) throws -> String.Index {
        var nesting = 1
        var index = value.index(after: opening)
        var closed = false
        // Nested `${...}` regions increment the depth so their braces cannot close the outer expression.
        while !closed, index < value.endIndex {
            let step = try advanceBrace(in: value, at: index, nesting: nesting)
            index = step.index
            nesting = step.nesting
            closed = step.closed
        }
        guard closed else {
            throw X8ConfigurationResolutionError.unsupportedExpansion
        }
        return index
    }

    static func nameEnd(in value: String, from start: String.Index) -> String.Index {
        var index = start
        while index < value.endIndex, isNameCharacter(value[index]) {
            index = value.index(after: index)
        }
        return index
    }

    static func isNameStart(_ character: Character) -> Bool {
        character == "_" || character.isLetter
    }

    private static func parseLengthExpression(_ expression: String) throws -> BracedExpression {
        let name = String(expression.dropFirst())
        guard isName(name) else {
            throw X8ConfigurationResolutionError.unsupportedExpansion
        }
        return .length(name)
    }

    private struct BraceStep {
        let index: String.Index
        let nesting: Int
        let closed: Bool
    }

    private static func advanceBrace(
        in value: String,
        at index: String.Index,
        nesting: Int
    ) throws -> BraceStep {
        if let nestedOpeningEnd = nestedOpeningEnd(in: value, at: index) {
            return BraceStep(index: nestedOpeningEnd, nesting: nesting + 1, closed: false)
        }
        var nextNesting = nesting
        if consumeClosingBrace(value[index], nesting: &nextNesting) {
            return BraceStep(index: index, nesting: nextNesting, closed: true)
        }
        guard index < value.index(before: value.endIndex) else {
            throw X8ConfigurationResolutionError.unsupportedExpansion
        }
        return BraceStep(
            index: value.index(after: index),
            nesting: nextNesting,
            closed: false
        )
    }

    private static func nestedOpeningEnd(in value: String, at index: String.Index) -> String.Index? {
        guard value[index] == "$" else { return nil }
        let next = value.index(after: index)
        guard next < value.endIndex, value[next] == "{" else { return nil }
        return value.index(after: next)
    }

    private static func consumeClosingBrace(_ character: Character, nesting: inout Int) -> Bool {
        guard character == "}" else { return false }
        nesting -= 1
        return nesting == 0
    }

    private static func isName(_ value: String) -> Bool {
        guard let first = value.first, isNameStart(first) else { return false }
        return value.dropFirst().allSatisfy(isNameCharacter)
    }

    private static func isNameCharacter(_ character: Character) -> Bool {
        isNameStart(character) || character.isNumber
    }
}
