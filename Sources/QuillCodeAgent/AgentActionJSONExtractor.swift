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

    private static func parseObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
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

        return candidates
    }
}
