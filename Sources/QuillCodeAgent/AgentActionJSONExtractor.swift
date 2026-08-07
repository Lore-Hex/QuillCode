import Foundation

enum AgentActionJSONExtractor {
    static func strippedFences(from text: String) -> String {
        var output = text
        if output.hasPrefix("```json") {
            output.removeFirst("```json".count)
        } else if output.hasPrefix("```") {
            output.removeFirst("```".count)
        }
        if output.hasSuffix("```") {
            output.removeLast("```".count)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func actionObject(
        in text: String,
        looksLikeAction: ([String: Any]) -> Bool
    ) -> [String: Any]? {
        if let object = parseObject(text), looksLikeAction(object) {
            return object
        }
        for candidate in jsonObjectCandidates(in: text) {
            guard let object = parseObject(candidate), looksLikeAction(object) else { continue }
            return object
        }
        return nil
    }

    /// Recovers a complete canonical file-write envelope whose content contains bare quote marks.
    /// Some providers repeat the same otherwise-complete action after corrective prompts while
    /// leaving prose quotes unescaped inside `content`. The strict shape and required closing braces
    /// keep this from treating a truncated stream or arbitrary prose as an executable write.
    static func fileWriteObjectByEscapingBareContentQuotes(in text: String) -> [String: Any]? {
        let fullRange = NSRange(text.startIndex..., in: text)
        guard text.first == "{",
              let nameRegex = try? NSRegularExpression(
                pattern: #"\"name\"\s*:\s*\"host\.file\.write\""#
              ),
              nameRegex.firstMatch(in: text, range: fullRange) != nil,
              let contentRegex = try? NSRegularExpression(pattern: #"\"content\"\s*:\s*\""#),
              let contentMarker = contentRegex.firstMatch(in: text, range: fullRange),
              let closingRegex = try? NSRegularExpression(pattern: #"\"\s*\}\s*\}\s*$"#),
              let closing = closingRegex.firstMatch(in: text, range: fullRange),
              contentMarker.range.location + contentMarker.range.length <= closing.range.location,
              let contentStart = Range(contentMarker.range, in: text)?.upperBound,
              let contentEnd = Range(closing.range, in: text)?.lowerBound
        else { return nil }

        let body = String(text[contentStart..<contentEnd])
        let repaired = String(text[..<contentStart])
            + escapingBareQuotes(in: body)
            + String(text[contentEnd...])
        return parseObject(repaired)
    }

    private static func parseObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func escapingBareQuotes(in body: String) -> String {
        var repaired = ""
        var backslashRun = 0
        for character in body {
            if character == "\"", backslashRun.isMultiple(of: 2) {
                repaired.append("\\")
            }
            repaired.append(character)
            backslashRun = character == "\\" ? backslashRun + 1 : 0
        }
        return repaired
    }

    private static func jsonObjectCandidates(in text: String) -> [String] {
        var candidates: [String] = []
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaping = false

        for index in text.indices {
            let character = text[index]
            guard let start = startIndex else {
                if character == "{" {
                    startIndex = index
                    depth = 1
                    isInsideString = false
                    isEscaping = false
                }
                continue
            }

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    candidates.append(String(text[start...index]))
                    startIndex = nil
                }
            }
        }

        // Some providers occasionally finish a complete tool payload but omit one or more
        // trailing object braces at EOF. Repair only that structural case: every JSON string
        // must already be closed, and JSONSerialization still validates the repaired object.
        if let start = startIndex, !isInsideString, depth > 0 {
            candidates.append(
                String(text[start...]) + String(repeating: "}", count: depth)
            )
        }

        return candidates
    }
}
