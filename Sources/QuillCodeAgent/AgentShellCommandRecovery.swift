import Foundation
import QuillCodeCore
import QuillCodeTools

enum AgentShellCommandRecovery {
    static func recoveredAction(from text: String) -> AgentAction? {
        guard let command = explicitCommand(from: text) else {
            return nil
        }
        return .tool(.init(
            name: ToolDefinition.shellRun.name,
            argumentsJSON: ToolArguments.json(["cmd": command])
        ))
    }

    static func explicitCommand(from text: String) -> String? {
        let spans = inlineCodeSpans(in: text)
        for span in spans {
            let command = span.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPlausibleShellCommand(command),
                  hasExecutionIntent(before: span.range.lowerBound, in: text)
            else {
                continue
            }
            return command
        }
        return nil
    }

    private static func inlineCodeSpans(in text: String) -> [(code: String, range: Range<String.Index>)] {
        var spans: [(String, Range<String.Index>)] = []
        var searchIndex = text.startIndex
        while searchIndex < text.endIndex,
              let opening = text[searchIndex...].firstIndex(of: "`") {
            let afterOpening = text.index(after: opening)
            guard afterOpening < text.endIndex else { break }
            if text[afterOpening] == "`" {
                searchIndex = afterOpening
                continue
            }
            guard let closing = text[afterOpening...].firstIndex(of: "`") else { break }
            if text[text.index(before: closing)] != "`" {
                spans.append((String(text[afterOpening..<closing]), opening..<text.index(after: closing)))
            }
            searchIndex = text.index(after: closing)
        }
        return spans
    }

    private static func hasExecutionIntent(before index: String.Index, in text: String) -> Bool {
        let lowerBound = text.index(index, offsetBy: -96, limitedBy: text.startIndex) ?? text.startIndex
        let prefix = text[lowerBound..<index]
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
        let negativeIntents = [
            "do not run",
            "don't run",
            "will not run",
            "won't run",
            "cannot run",
            "can't run",
            "should not run",
            "do not execute",
            "don't execute",
            "will not execute",
            "won't execute"
        ]
        guard !negativeIntents.contains(where: { prefix.contains($0) }) else {
            return false
        }
        let intents = [
            "i'll run",
            "i’ll run",
            "i will run",
            "i'll execute",
            "i’ll execute",
            "i will execute",
            "i'll check",
            "i’ll check",
            "i will check",
            "i am running",
            "i'm running",
            "i’m running",
            "running",
            "run ",
            "execute "
        ]
        return intents.contains { prefix.contains($0) }
    }

    private static func isPlausibleShellCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\n"),
              trimmed.count <= 500
        else {
            return false
        }
        let firstWord = trimmed.split(separator: " ", maxSplits: 1).first.map(String.init) ?? trimmed
        guard firstWord.range(of: #"^[A-Za-z0-9_./:-]+$"#, options: .regularExpression) != nil else {
            return false
        }
        return true
    }
}
