import Foundation

enum ToolArtifactCodeClimateJSONPreviewBuilder {
    static func codeClimateJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactCodeClimateJSONPreview? {
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
            guard let issues = root as? [[String: Any]] else { return nil }
            return preview(
                from: issues,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(
        from issues: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactCodeClimateJSONPreview? {
        guard !issues.isEmpty, issues.allSatisfy(hasCodeClimateIssueShape) else { return nil }

        var fileLabels: [String] = []
        var checkLabels: [String] = []
        var categoryLabels: [String] = []
        var blockerCount = 0
        var criticalCount = 0
        var majorCount = 0
        var minorCount = 0
        var infoCount = 0
        var otherSeverityCount = 0

        for issue in issues {
            if let path = locationPath(in: issue) {
                appendUnique(sanitizedPathLabel(path), to: &fileLabels, limit: previewLimit)
            }
            if let checkName = stringValue(issue["check_name"]) {
                appendUnique(sanitizedLabel(checkName), to: &checkLabels, limit: previewLimit)
            }
            for category in issue["categories"] as? [String] ?? [] {
                appendUnique(sanitizedLabel(category), to: &categoryLabels, limit: previewLimit)
            }

            switch stringValue(issue["severity"])?.lowercased() {
            case "blocker":
                blockerCount += 1
            case "critical":
                criticalCount += 1
            case "major":
                majorCount += 1
            case "minor":
                minorCount += 1
            case "info":
                infoCount += 1
            default:
                otherSeverityCount += 1
            }
        }

        return ToolArtifactCodeClimateJSONPreview(
            issueCount: issues.count,
            fileCount: uniqueCount(in: issues, value: locationPath),
            checkCount: uniqueCount(in: issues) { stringValue($0["check_name"]) },
            categoryCount: Set(issues.flatMap { $0["categories"] as? [String] ?? [] }).count,
            blockerCount: blockerCount,
            criticalCount: criticalCount,
            majorCount: majorCount,
            minorCount: minorCount,
            infoCount: infoCount,
            otherSeverityCount: otherSeverityCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            checkPreviewLabels: checkLabels,
            categoryPreviewLabels: categoryLabels
        )
    }

    private static func hasCodeClimateIssueShape(_ issue: [String: Any]) -> Bool {
        guard stringValue(issue["type"]) == "issue",
              stringValue(issue["check_name"]) != nil,
              stringValue(issue["description"]) != nil,
              locationPath(in: issue) != nil
        else {
            return false
        }
        return issue["categories"] is [String]
            || issue.keys.contains("severity")
            || stringValue(issue["fingerprint"]) != nil
    }

    private static func locationPath(in issue: [String: Any]) -> String? {
        guard let location = issue["location"] as? [String: Any] else { return nil }
        return stringValue(location["path"])
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
