import Foundation

enum ToolArtifactTAPPreviewBuilder {
    static func tapPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactTAPPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "tap",
              let fileURL = localArtifactFileURL(for: value)
        else {
            return nil
        }

        do {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues.isRegularFile == true else { return nil }
            let fileSize = max(resourceValues.fileSize ?? 0, 0)
            guard fileSize > 0, fileSize <= byteLimit else { return nil }
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            guard !data.contains(0),
                  var text = String(data: data, encoding: .utf8)
            else { return nil }
            text = text
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            return preview(
                from: text,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(from text: String, byteSizeLabel: String?) -> ToolArtifactTAPPreview? {
        var planLabel: String?
        var assertionCount = 0
        var passedCount = 0
        var failedCount = 0
        var skippedCount = 0
        var todoCount = 0
        var bailoutLabel: String?
        var failures: [String] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(lineLimit) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            if let plan = parsePlan(line) {
                planLabel = plan
                continue
            }
            if line.lowercased().hasPrefix("bail out!") {
                bailoutLabel = sanitizedLabel(String(line.dropFirst("Bail out!".count)))
                continue
            }
            guard let assertion = parseAssertion(line) else {
                continue
            }
            assertionCount += 1
            if assertion.isTodo {
                todoCount += 1
            }
            if assertion.isSkipped {
                skippedCount += 1
            }
            if assertion.isPassing || assertion.isTodo {
                passedCount += 1
            } else {
                failedCount += 1
                if failures.count < failurePreviewLimit {
                    failures.append(assertion.label)
                }
            }
        }

        guard assertionCount > 0 || planLabel != nil || bailoutLabel != nil else { return nil }
        return ToolArtifactTAPPreview(
            planLabel: planLabel,
            assertionCount: assertionCount,
            passedCount: passedCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            todoCount: todoCount,
            bailoutLabel: bailoutLabel,
            byteSizeLabel: byteSizeLabel,
            failurePreviewLabels: failures
        )
    }

    private static func parsePlan(_ line: String) -> String? {
        guard line.range(of: #"^\d+\.\.\d+"#, options: .regularExpression) != nil else {
            return nil
        }
        return sanitizedLabel(line)
    }

    private static func parseAssertion(_ line: String) -> Assertion? {
        let lowercased = line.lowercased()
        let isPassing: Bool
        let remainder: Substring
        if lowercased.hasPrefix("ok") {
            isPassing = true
            remainder = line.dropFirst(2)
        } else if lowercased.hasPrefix("not ok") {
            isPassing = false
            remainder = line.dropFirst(6)
        } else {
            return nil
        }

        let detail = String(remainder).trimmingCharacters(in: .whitespaces)
        let directive = directive(in: detail)
        let label = sanitizedLabel(detail.isEmpty ? line : detail)
        return Assertion(
            isPassing: isPassing,
            isSkipped: directive == "skip",
            isTodo: directive == "todo",
            label: label
        )
    }

    private static func directive(in detail: String) -> String? {
        guard let hash = detail.firstIndex(of: "#") else { return nil }
        let directive = detail[detail.index(after: hash)...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if directive.hasPrefix("skip") {
            return "skip"
        }
        if directive.hasPrefix("todo") {
            return "todo"
        }
        return nil
    }

    private static func localArtifactFileURL(for value: String) -> URL? {
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        guard let url = URL(string: value),
              url.scheme?.lowercased() == "file"
        else {
            return nil
        }
        return url
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "Unnamed assertion" : collapsedWhitespace).prefix(characterLimit))
    }

    private struct Assertion {
        var isPassing: Bool
        var isSkipped: Bool
        var isTodo: Bool
        var label: String
    }

    private static let byteLimit = 512 * 1_024
    private static let lineLimit = 20_000
    private static let failurePreviewLimit = 6
    private static let characterLimit = 96
}
