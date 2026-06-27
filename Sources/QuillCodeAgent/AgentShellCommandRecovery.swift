import Foundation
import QuillCodeCore
import QuillCodeTools

enum AgentShellCommandRecovery {
    private static let negativeExecutionIntents = [
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
    private static let inlineExecutionIntents = [
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
    private static let plainExecutionMarkers = [
        "i'll run ",
        "i’ll run ",
        "i will run ",
        "i'll execute ",
        "i’ll execute ",
        "i will execute ",
        "i'll check ",
        "i’ll check ",
        "i will check ",
        "i am running ",
        "i'm running ",
        "i’m running ",
        "running ",
        "run ",
        "execute ",
        "check "
    ]
    private static let standaloneImperativeMarkers = ["run ", "execute ", "check "]
    private static let plainCommandPlaceholders = [
        "it",
        "that",
        "this",
        "the command",
        "a command",
        "the requested command",
        "the shell command"
    ]
    private static let trailingDiscoursePhrases = [
        " on the device",
        " on your device",
        " for you",
        " now",
        " next",
        " and show",
        " and report",
        " and return",
        " then "
    ]
    private static let knownPlainShellCommands: Set<String> = [
        "awk",
        "cat",
        "command",
        "curl",
        "date",
        "df",
        "du",
        "echo",
        "find",
        "git",
        "grep",
        "id",
        "ls",
        "make",
        "mkdir",
        "node",
        "npm",
        "printf",
        "pwd",
        "python",
        "python3",
        "rg",
        "sed",
        "swift",
        "touch",
        "uname",
        "wc",
        "which",
        "whoami",
        "xcodebuild"
    ]

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
        return plainExecutionCommand(in: text)
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
        guard !containsNegativeExecutionIntent(prefix) else {
            return false
        }
        return inlineExecutionIntents.contains { prefix.contains($0) }
    }

    private static func plainExecutionCommand(in text: String) -> String? {
        let compactText = text.replacingOccurrences(of: "\n", with: " ")
        let lower = compactText.lowercased()
        guard !containsNegativeExecutionIntent(lower) else {
            return nil
        }

        for marker in plainExecutionMarkers {
            guard let markerRange = lower.range(of: marker) else { continue }
            guard isPlainExecutionMarkerAllowed(marker, range: markerRange, in: compactText) else {
                continue
            }
            let commandStart = markerRange.upperBound
            let rawCandidate = String(compactText[commandStart...])
            let command = trimmedPlainCommand(from: rawCandidate)
            if isPlausiblePlainCommand(command) {
                return command
            }
        }
        return nil
    }

    private static func isPlainExecutionMarkerAllowed(
        _ marker: String,
        range: Range<String.Index>,
        in text: String
    ) -> Bool {
        guard standaloneImperativeMarkers.contains(marker) else {
            return true
        }
        let prefix = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return prefix.isEmpty
    }

    private static func containsNegativeExecutionIntent(_ text: String) -> Bool {
        negativeExecutionIntents.contains { text.contains($0) }
    }

    private static func trimmedPlainCommand(from rawCandidate: String) -> String {
        var candidate = rawCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if let boundary = sentenceBoundary(in: candidate) {
            candidate = String(candidate[..<boundary])
        }
        candidate = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’ "))
        candidate = trimTrailingDiscourse(from: candidate)
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sentenceBoundary(in text: String) -> String.Index? {
        var index = text.startIndex
        while index < text.endIndex {
            guard ".?!".contains(text[index]) else {
                index = text.index(after: index)
                continue
            }
            let next = text.index(after: index)
            if next == text.endIndex || text[next].isWhitespace {
                return index
            }
            index = next
        }
        return nil
    }

    private static func trimTrailingDiscourse(from command: String) -> String {
        var output = command
        while true {
            let lower = output.lowercased()
            guard let phrase = trailingDiscoursePhrases.first(where: { lower.hasSuffix($0) }) else {
                return output
            }
            output.removeLast(phrase.count)
            output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func isPlausiblePlainCommand(_ command: String) -> Bool {
        guard isPlausibleShellCommand(command) else {
            return false
        }
        let lower = command.lowercased()
        guard !plainCommandPlaceholders.contains(lower) else {
            return false
        }
        let firstWord = lower.split(separator: " ", maxSplits: 1).first.map(String.init) ?? lower
        return knownPlainShellCommands.contains(firstWord)
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
