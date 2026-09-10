/// Matches the full value against the glob subset used by parameter expansion.
///
/// `*` matches any number of characters and `?` matches one character. All
/// other characters are literals. This helper is not a regular-expression or
/// shell evaluator; it exists only for `${name#pattern}` and
/// `${name%pattern}`-style expansion.
package enum ShellPatternMatcher {
    /// Returns whether a pattern matches the complete value.
    package static func matches(_ pattern: String, _ value: String) -> Bool {
        let pattern = Array(pattern)
        let value = Array(value)
        var state = State()

        // Remember the last star so a later literal mismatch can retry with one more consumed character.
        while state.valueIndex < value.count, let next = advance(pattern: pattern, value: value, state: state) {
            state = next
        }

        guard state.valueIndex == value.count else {
            return false
        }

        while state.patternIndex < pattern.count, pattern[state.patternIndex] == "*" {
            state.patternIndex += 1
        }
        return state.patternIndex == pattern.count
    }

    private struct State {
        var patternIndex = 0
        var valueIndex = 0
        var lastStar: Int?
        var starMatch = 0
    }

    private enum Step {
        case character
        case star
        case backtrack(Int)
        case mismatch
    }

    private static func advance(
        pattern: [Character],
        value: [Character],
        state: State
    ) -> State? {
        switch step(pattern: pattern, value: value, state: state) {
        case .character:
            var next = state
            next.patternIndex += 1
            next.valueIndex += 1
            return next
        case .star:
            var next = state
            next.patternIndex += 1
            next.lastStar = state.patternIndex
            next.starMatch = state.valueIndex
            return next
        case let .backtrack(starIndex):
            var next = state
            next.patternIndex = starIndex + 1
            next.starMatch += 1
            next.valueIndex = next.starMatch
            return next
        case .mismatch:
            return nil
        }
    }

    private static func step(
        pattern: [Character],
        value: [Character],
        state: State
    ) -> Step {
        guard state.patternIndex < pattern.count else {
            return state.lastStar.map(Step.backtrack) ?? .mismatch
        }
        let character = pattern[state.patternIndex]
        if character == "?" || character == value[state.valueIndex] {
            return .character
        }
        if character == "*" {
            return .star
        }
        return state.lastStar.map(Step.backtrack) ?? .mismatch
    }
}
