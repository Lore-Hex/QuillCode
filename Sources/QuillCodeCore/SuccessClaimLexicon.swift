import Foundation

/// The data-driven lexicon of assistant success claims. Phrases are matched with
/// token boundaries so incidental words in prose do not trip UNVERIFIED.
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
        for phrase in claimPhrases where TestCommandLexicon.containsToken(phrase, in: loweredText) {
            return phrase
        }
        return nil
    }
}
