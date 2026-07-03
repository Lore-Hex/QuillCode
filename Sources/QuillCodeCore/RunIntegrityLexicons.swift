import Foundation

/// The data-driven lexicon of what a "test / verify" command looks like. A token matches only on a
/// word boundary so `pytest` matches but `mypytesting` does not, and `test` alone is intentionally not a
/// token because commands like `test -f` are normal shell control flow.
public enum TestCommandLexicon {
    /// Standalone test-runner invocations.
    public static let runnerTokens: [String] = [
        "swift test",
        "xcodebuild test",
        "xctest",
        "pytest",
        "py.test",
        "unittest",
        "jest",
        "vitest",
        "mocha",
        "rspec",
        "phpunit",
        "gotestsum",
        "ctest",
        "tox",
        "nosetests",
    ]

    /// `<tool> test` sub-command shapes, for example `cargo test`, `npm test`, or `go test`.
    public static let subcommandTokens: [String] = [
        "cargo test",
        "go test",
        "npm test",
        "npm run test",
        "yarn test",
        "pnpm test",
        "bun test",
        "make test",
        "make check",
        "gradle test",
        "./gradlew test",
        "mvn test",
        "dotnet test",
        "rake test",
        "bazel test",
        "ninja test",
    ]

    public static func looksLikeTestCommand(_ command: String) -> Bool {
        let lowered = command.lowercased()
        guard !lowered.isEmpty else { return false }
        for token in runnerTokens + subcommandTokens where containsToken(token, in: lowered) {
            return true
        }
        return false
    }

    /// Substring match with cheap word-ish boundaries so a token embedded in a longer identifier does
    /// not match. Bounded and allocation-light.
    static func containsToken(_ token: String, in haystack: String) -> Bool {
        var searchRange = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: token, options: [], range: searchRange) {
            let beforeOK = found.lowerBound == haystack.startIndex
                || !isWordScalar(haystack[haystack.index(before: found.lowerBound)])
            let afterOK = found.upperBound == haystack.endIndex
                || !isWordScalar(haystack[found.upperBound])
            if beforeOK && afterOK { return true }
            if found.upperBound >= haystack.endIndex { break }
            searchRange = haystack.index(after: found.lowerBound)..<haystack.endIndex
        }
        return false
    }

    static func isWordScalar(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

/// The data-driven lexicon of assistant success claims. Anchored so an incidental "passes" in prose
/// does not trip UNVERIFIED; every phrase reads as a claim about tests/checks passing.
public enum SuccessClaimLexicon {
    public static let claimPhrases: [String] = [
        "tests pass",
        "tests passed",
        "tests are passing",
        "all tests pass",
        "all tests passed",
        "all tests passing",
        "all tests are passing",
        "test suite passes",
        "test suite passed",
        "tests are green",
        "all green",
        "everything passes",
        "everything is passing",
        "all checks pass",
        "all checks passed",
        "checks pass",
        "build passes",
        "build passed",
        "verified the tests",
        "tests now pass",
        "the tests pass",
    ]

    public static func matchedClaim(in loweredText: String) -> String? {
        guard !loweredText.isEmpty else { return nil }
        for phrase in claimPhrases where loweredText.contains(phrase) {
            return phrase
        }
        return nil
    }
}
