/// Expands X8's restricted scalar parameter forms without invoking a shell.
///
/// It reads named environment values and supports the braced default,
/// assignment, required, alternative, length, and pattern forms accepted by
/// the configuration schema. Shell command substitution, control operators,
/// and process-state expansion are rejected. Assignment forms update only the
/// expander's private copy, and nested expressions are bounded to prevent
/// unbounded recursion.
///
/// The type is package-visible because configuration resolution is its only
/// production caller; the separate boundary keeps the grammar independently
/// testable without making it part of the public Kit API.
package struct ScalarParameterExpander: Sendable {
    private static let maximumDepth = 32

    private var environment: [String: String]

    /// Creates an expander with an isolated environment copy.
    package init(environment: [String: String]) {
        self.environment = environment
    }

    /// Expands one scalar value using this instance's isolated environment.
    ///
    /// Assignment-style expressions can affect later expansions performed by
    /// this same instance, but never the process environment or another
    /// expander.
    package mutating func expand(_ value: String) throws -> String {
        try expand(value, depth: 0)
    }

    private mutating func expand(_ value: String, depth: Int) throws -> String {
        guard depth <= Self.maximumDepth else {
            throw X8ConfigurationResolutionError.expansionDepthExceeded
        }
        guard !value.contains(where: { "|;&<>".contains($0) }) else {
            throw X8ConfigurationResolutionError.unsupportedExpansion
        }

        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let expansion = try expandSegment(in: value, at: index, depth: depth)
            result.append(expansion.replacement)
            index = expansion.nextIndex
        }
        return result
    }

    private mutating func expandSegment(
        in value: String,
        at index: String.Index,
        depth: Int
    ) throws -> (replacement: String, nextIndex: String.Index) {
        let character = value[index]
        if character == "`" {
            throw X8ConfigurationResolutionError.unsupportedExpansion
        }
        guard character == "$" else {
            return (String(character), value.index(after: index))
        }
        return try expandVariable(in: value, at: index, depth: depth)
    }

    private mutating func expandVariable(
        in value: String,
        at dollar: String.Index,
        depth: Int
    ) throws -> (replacement: String, nextIndex: String.Index) {
        let next = value.index(after: dollar)
        guard next < value.endIndex else {
            return ("$", value.endIndex)
        }
        if value[next] == "$" {
            // `$$` is an escaped literal dollar sign, not the start of a variable name.
            return ("$", value.index(after: next))
        }
        // X8 expands named environment variables only; shell process state is unavailable here.
        if value[next] == "`" || value[next] == "(" || value[next] == "?"
            || value[next] == "!" || value[next] == "@" || value[next] == "*"
            || value[next] == "#" || value[next] == "-" || value[next].isNumber
        {
            throw X8ConfigurationResolutionError.unsupportedExpansion
        }
        if value[next] == "{" {
            let closing = try ScalarParameterSyntax.closingBrace(in: value, after: next)
            let expressionStart = value.index(after: next)
            let expression = String(value[expressionStart ..< closing])
            let replacement = try expandBraced(expression, depth: depth + 1)
            return (replacement, value.index(after: closing))
        }
        guard ScalarParameterSyntax.isNameStart(value[next]) else {
            return ("$", next)
        }
        let nameEnd = ScalarParameterSyntax.nameEnd(in: value, from: next)
        return (environment[String(value[next ..< nameEnd])] ?? "", nameEnd)
    }

    private mutating func expandBraced(_ expression: String, depth: Int) throws -> String {
        let parsed = try ScalarParameterSyntax.parseBraced(expression)
        // Parse before expanding operands so nested expressions share one depth guard.
        switch parsed {
        case let .length(name):
            return String((environment[name] ?? "").count)
        case let .value(name):
            return environment[name] ?? ""
        case let .pattern(name, pattern, prefix, longest):
            // Pattern operands are expanded independently before matching the value.
            let expandedPattern = try expand(pattern, depth: depth)
            return removePattern(
                from: environment[name] ?? "",
                pattern: expandedPattern,
                prefix: prefix,
                longest: longest
            )
        case let .conditional(name, operation, word):
            let expandedWord = try expand(word, depth: depth)
            return try apply(operation, to: name, word: expandedWord)
        }
    }

    private mutating func apply(
        _ operation: ScalarParameterSyntax.ConditionalOperation,
        to name: String,
        word: String
    ) throws -> String {
        let value = environment[name]
        let isSet = value != nil
        let isAvailable = operation.requiresNonEmpty ? value?.isEmpty == false : isSet
        switch operation {
        case .defaultValue where !isAvailable:
            return word
        case .assignValue where !isAvailable:
            environment[name] = word
            return word
        case .requiredValue where !isAvailable:
            throw X8ConfigurationResolutionError.requiredEnvironmentVariable(name)
        case .alternative where isAvailable:
            return word
        default:
            return value ?? ""
        }
    }

    private func removePattern(
        from value: String,
        pattern: String,
        prefix: Bool,
        longest: Bool
    ) -> String {
        // `length` is the candidate pattern length, not the remaining value length.
        // Ascending search removes the shortest match; descending search removes the longest.
        let lengths = stride(
            from: longest ? value.count : 0,
            through: longest ? 0 : value.count,
            by: longest ? -1 : 1
        )
        guard let length = lengths.first(where: { length in
            let boundary = value.index(
                value.startIndex,
                offsetBy: prefix ? length : value.count - length
            )
            let candidate = prefix ? String(value[..<boundary]) : String(value[boundary...])
            return ShellPatternMatcher.matches(pattern, candidate)
        }) else {
            return value
        }
        let boundary = value.index(
            value.startIndex,
            offsetBy: prefix ? length : value.count - length
        )
        return prefix ? String(value[boundary...]) : String(value[..<boundary])
    }
}
