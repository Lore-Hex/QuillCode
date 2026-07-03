import Foundation

/// The data-driven lexicon of what a "test / verify" command looks like.
///
/// The precision rule that governs this type: a command is a test command only
/// when the test runner is in command position, meaning argv[0] in one of the
/// command's control-operator-separated segments after recognized wrappers are
/// stripped. `pytest tests/` is a test command; `grep -rn pytest .`, `which
/// pytest`, and `grep -q 'go test' Makefile` are not.
public enum TestCommandLexicon {
    /// The parsed test-command identity for a command line.
    ///
    /// `scope` is the identity used to decide whether the same test was re-run:
    /// runner plus normalized target arguments. This prevents a green unrelated
    /// suite from clearing a different suite's failure.
    public struct Match: Sendable, Hashable {
        /// The recognized runner in command position, such as `pytest`,
        /// `swift test`, or `xcodebuild test`.
        public var runner: String
        /// Normalized invocation identity for same-scope re-run matching.
        public var scope: String
    }

    /// Classifies a shell command line, returning a `Match` when a test runner
    /// is in command position in any segment.
    public static func classify(_ command: String) -> Match? {
        let lowered = command.lowercased()
        guard !lowered.isEmpty else { return nil }
        for segment in commandSegments(in: lowered) {
            if let match = classifySegment(segment) {
                return match
            }
        }
        return nil
    }

    /// Back-compat boolean wrapper.
    public static func looksLikeTestCommand(_ command: String) -> Bool {
        classify(command) != nil
    }
}
