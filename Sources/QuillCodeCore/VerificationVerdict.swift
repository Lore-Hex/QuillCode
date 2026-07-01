import Foundation

/// The outcome of running a project's verification command (its `test` / `verify` / `check` action)
/// after an edit-bearing run — the fact behind whether "finished" is actually GREEN.
public enum VerificationVerdict: Sendable, Hashable {
    /// The command exited 0.
    case passed
    /// The command exited non-zero. `count` is the number of failing checks when one could be parsed
    /// from the output, else nil (so the notice says "checks failing" rather than a fabricated number).
    case failed(count: Int?)
    /// The command exceeded its timeout — not a green claim.
    case timedOut
    /// The command could not be run (exit 127 / not found).
    case commandNotFound
}

/// Turns a verification command's `ToolResult` into a `VerificationVerdict`. Pure — no I/O — so the
/// classification (and the fragile failure-count parsing) is fully unit-tested. Timeouts are decided by
/// the executor (which knows it killed the command) and passed as `.timedOut` directly, not string-
/// matched here.
public enum VerificationResultParser {
    public static func parse(_ result: ToolResult) -> VerificationVerdict {
        if result.ok { return .passed }
        // The shell executor reports a timeout in `error` ("Command timed out after Ns.") — surface it
        // distinctly, since a timeout is not the same as failing checks.
        if let error = result.error, error.range(of: "timed out", options: .caseInsensitive) != nil {
            return .timedOut
        }
        // 127 is the shell's "command not found"; treat it as unrunnable, not a real failure.
        if result.exitCode == 127 { return .commandNotFound }
        return .failed(count: failureCount(in: result.stdout + "\n" + result.stderr))
    }

    /// A best-effort count of failing checks across the common test-runner output shapes. Returns the
    /// FIRST match; nil when nothing matches (never a fabricated number).
    static func failureCount(in text: String) -> Int? {
        let patterns = [
            #"(\d+)\s+failed"#,
            #"(\d+)\s+failing"#,
            #"(\d+)\s+tests?\s+failed"#,
            // Swift/XCTest: "Executed N tests, with 3 failures"; also "3 failures".
            #"(\d+)\s+failures?\b"#,
            #"failures?\s*[=:]\s*(\d+)"#,
        ]
        for pattern in patterns {
            if let count = firstCapturedInt(pattern, in: text), count > 0 {
                return count
            }
        }
        return nil
    }

    private static func firstCapturedInt(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let captured = Range(match.range(at: 1), in: text),
              let value = Int(text[captured])
        else {
            return nil
        }
        return value
    }
}
