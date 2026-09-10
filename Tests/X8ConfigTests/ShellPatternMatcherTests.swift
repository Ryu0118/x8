import Testing
@testable import X8Config

@Suite("Shell-style parameter patterns")
struct ShellPatternMatcherTests {
    @Test
    func starMatchesEmptyAndMultipleCharacters() {
        #expect(ShellPatternMatcher.matches("foo*bar", "foobar"))
        #expect(ShellPatternMatcher.matches("foo*bar", "foo-middle-bar"))
        #expect(!ShellPatternMatcher.matches("foo*bar", "foo-middle-baz"))
        #expect(ShellPatternMatcher.matches("*", ""))
        #expect(ShellPatternMatcher.matches("**", "value"))
    }

    @Test
    func questionMarkMatchesExactlyOneCharacter() {
        #expect(ShellPatternMatcher.matches("foo?bar", "foo/bar"))
        #expect(!ShellPatternMatcher.matches("foo?bar", "foobar"))
        #expect(!ShellPatternMatcher.matches("foo?bar", "foo/long/bar"))
    }

    @Test
    func patternsMustMatchTheCompleteValue() {
        #expect(!ShellPatternMatcher.matches("foo", "prefix-foo"))
        #expect(!ShellPatternMatcher.matches("foo", "foo-suffix"))
        #expect(ShellPatternMatcher.matches("日本*", "日本語"))
    }
}
