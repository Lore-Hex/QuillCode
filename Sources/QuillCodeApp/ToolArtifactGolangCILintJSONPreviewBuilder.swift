import Foundation

enum ToolArtifactGolangCILintJSONPreviewBuilder {
    static func golangCILintJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactGolangCILintJSONPreview? {
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
    ) -> ToolArtifactGolangCILintJSONPreview? {
        guard let issues = report["Issues"] as? [[String: Any]],
              !issues.isEmpty,
              issues.allSatisfy(hasGolangCILintIssueShape)
        else {
            return nil
        }

        var severityCounts: [String: Int] = [:]
        var fileLabels: [String] = []
        var linterLabels: [String] = []

        for issue in issues {
            if let linter = stringValue(issue["FromLinter"]) {
                appendUnique(sanitizedLabel(linter), to: &linterLabels, limit: previewLimit)
            }
            if let severity = stringValue(issue["Severity"])?.lowercased() {
                severityCounts[severity, default: 0] += 1
            }
            if let position = issue["Pos"] as? [String: Any],
               let filename = stringValue(position["Filename"]) {
                appendUnique(sanitizedPathLabel(filename), to: &fileLabels, limit: previewLimit)
            }
        }

        guard !fileLabels.isEmpty || !linterLabels.isEmpty else { return nil }

        let knownSeverities = ["error", "warning", "info"]
        let otherSeverityCount = severityCounts
            .filter { !knownSeverities.contains($0.key) }
            .map(\.value)
            .reduce(0, +)

        return ToolArtifactGolangCILintJSONPreview(
            issueCount: issues.count,
            fileCount: uniqueFileCount(in: issues),
            linterCount: uniqueLinterCount(in: issues),
            errorCount: severityCounts["error"] ?? 0,
            warningCount: severityCounts["warning"] ?? 0,
            infoCount: severityCounts["info"] ?? 0,
            otherSeverityCount: otherSeverityCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            linterPreviewLabels: linterLabels
        )
    }

    private static func hasGolangCILintIssueShape(_ issue: [String: Any]) -> Bool {
        guard stringValue(issue["FromLinter"]) != nil,
              stringValue(issue["Text"]) != nil,
              let position = issue["Pos"] as? [String: Any],
              stringValue(position["Filename"]) != nil
        else {
            return false
        }
        return position.keys.contains("Line")
            || position.keys.contains("Column")
            || position.keys.contains("Offset")
    }

    private static func uniqueFileCount(in issues: [[String: Any]]) -> Int {
        Set(issues.compactMap { issue in
            (issue["Pos"] as? [String: Any]).flatMap { stringValue($0["Filename"]) }
        }).count
    }

    private static func uniqueLinterCount(in issues: [[String: Any]]) -> Int {
        Set(issues.compactMap { stringValue($0["FromLinter"]) }).count
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
