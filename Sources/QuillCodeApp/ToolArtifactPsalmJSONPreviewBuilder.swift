import Foundation

enum ToolArtifactPsalmJSONPreviewBuilder {
    static func psalmJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPsalmJSONPreview? {
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
            guard let report = root as? [String: Any] else { return nil }
            return preview(
                from: report,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(
        from report: [String: Any],
        byteSizeLabel: String?
    ) -> ToolArtifactPsalmJSONPreview? {
        let errors = issueList(in: report, key: "error")
        let warnings = issueList(in: report, key: "warning")
        let deprecations = issueList(in: report, key: "deprecation")
        let infos = issueList(in: report, key: "info")
        let allIssues = errors + warnings + deprecations + infos

        guard !allIssues.isEmpty,
              report.keys.contains(where: recognizedSeverityKeys.contains),
              allIssues.allSatisfy(hasPsalmIssueShape)
        else {
            return nil
        }

        var fileLabels: [String] = []
        var typeLabels: [String] = []
        for issue in allIssues {
            if let file = filePath(in: issue) {
                appendUnique(sanitizedPathLabel(file), to: &fileLabels, limit: previewLimit)
            }
            if let type = stringValue(issue["type"]) {
                appendUnique(sanitizedLabel(type), to: &typeLabels, limit: previewLimit)
            }
        }

        guard !fileLabels.isEmpty else { return nil }

        return ToolArtifactPsalmJSONPreview(
            issueCount: allIssues.count,
            fileCount: uniqueCount(in: allIssues, value: filePath),
            typeCount: uniqueCount(in: allIssues) { stringValue($0["type"]) },
            errorCount: errors.count,
            warningCount: warnings.count,
            deprecationCount: deprecations.count,
            infoCount: infos.count,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            typePreviewLabels: typeLabels
        )
    }

    private static func issueList(in report: [String: Any], key: String) -> [[String: Any]] {
        report[key] as? [[String: Any]] ?? []
    }

    private static func hasPsalmIssueShape(_ issue: [String: Any]) -> Bool {
        guard stringValue(issue["message"]) != nil,
              filePath(in: issue) != nil
        else {
            return false
        }
        return stringValue(issue["type"]) != nil
            || numericValue(issue["line_from"]) != nil
            || numericValue(issue["line"]) != nil
    }

    private static func filePath(in issue: [String: Any]) -> String? {
        stringValue(issue["file_name"])
            ?? stringValue(issue["file_path"])
            ?? stringValue(issue["file"])
    }

    private static func uniqueCount(
        in issues: [[String: Any]],
        value: ([String: Any]) -> String?
    ) -> Int {
        Set(issues.compactMap(value)).count
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

    private static func stringValue(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func numericValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = stringValue(value) {
            return Double(string)
        }
        return nil
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

    private static let recognizedSeverityKeys: Set<String> = ["error", "warning", "deprecation", "info"]
    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
