import Foundation

enum ToolArtifactESLintJSONPreviewBuilder {
    static func eslintJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactESLintJSONPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "json",
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
            guard !data.contains(0) else { return nil }
            let root = try JSONSerialization.jsonObject(with: data, options: [])
            guard let results = root as? [[String: Any]] else { return nil }
            return preview(
                from: results,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(
        from results: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactESLintJSONPreview? {
        guard !results.isEmpty, results.allSatisfy(hasESLintResultShape) else { return nil }

        var messageCount = 0
        var errorCount = 0
        var warningCount = 0
        var fixableCount = 0
        var fileLabels: [String] = []
        var ruleLabels: [String] = []

        for result in results {
            if let filePath = stringValue(result["filePath"]) {
                appendUnique(sanitizedPathLabel(filePath), to: &fileLabels, limit: previewLimit)
            }
            let messages = result["messages"] as? [[String: Any]] ?? []
            messageCount += messages.count
            errorCount += intValue(result["errorCount"]) ?? messages.filter { severityValue($0["severity"]) == 2 }.count
            warningCount += intValue(result["warningCount"]) ?? messages.filter { severityValue($0["severity"]) == 1 }.count
            let explicitFixableCount = (intValue(result["fixableErrorCount"]) ?? 0)
                + (intValue(result["fixableWarningCount"]) ?? 0)
            fixableCount += explicitFixableCount > 0
                ? explicitFixableCount
                : messages.filter { $0["fix"] != nil }.count
            for message in messages {
                guard let ruleID = stringValue(message["ruleId"]) else { continue }
                appendUnique(sanitizedLabel(ruleID), to: &ruleLabels, limit: previewLimit)
            }
        }

        guard messageCount > 0
                || errorCount > 0
                || warningCount > 0
                || !fileLabels.isEmpty
        else { return nil }

        return ToolArtifactESLintJSONPreview(
            fileCount: results.count,
            messageCount: messageCount,
            errorCount: errorCount,
            warningCount: warningCount,
            fixableCount: fixableCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            rulePreviewLabels: ruleLabels
        )
    }

    private static func hasESLintResultShape(_ result: [String: Any]) -> Bool {
        guard stringValue(result["filePath"]) != nil,
              result["messages"] is [[String: Any]]
        else {
            return false
        }
        return result.keys.contains("errorCount")
            || result.keys.contains("warningCount")
            || result.keys.contains("fixableErrorCount")
            || result.keys.contains("fixableWarningCount")
            || !(result["messages"] as? [[String: Any]] ?? []).isEmpty
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

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func severityValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func appendUnique(_ value: String, to values: inout [String], limit: Int) {
        guard values.count < limit, !values.contains(value) else { return }
        values.append(value)
    }

    private static func sanitizedPathLabel(_ value: String) -> String {
        let trimmed = sanitizedLabel(value)
        guard trimmed.hasPrefix("/") else { return trimmed }
        let components = trimmed.split(separator: "/")
        return components.suffix(3).joined(separator: "/")
    }

    private static func sanitizedLabel(_ value: String) -> String {
        let collapsedWhitespace = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "Unknown" : collapsedWhitespace).prefix(characterLimit))
    }

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
