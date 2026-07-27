import Foundation

enum ToolArtifactRuboCopJSONPreviewBuilder {
    static func rubocopJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactRuboCopJSONPreview? {
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
    ) -> ToolArtifactRuboCopJSONPreview? {
        guard hasRuboCopReportShape(report),
              let files = report["files"] as? [[String: Any]],
              !files.isEmpty,
              files.allSatisfy(hasRuboCopFileShape)
        else {
            return nil
        }

        var offenseCount = 0
        var severityCounts: [String: Int] = [:]
        var correctableCount = 0
        var fileLabels: [String] = []
        var copLabels: [String] = []

        for file in files {
            if let path = stringValue(file["path"]) {
                appendUnique(sanitizedPathLabel(path), to: &fileLabels, limit: previewLimit)
            }

            let offenses = file["offenses"] as? [[String: Any]] ?? []
            offenseCount += offenses.count
            for offense in offenses {
                if let severity = stringValue(offense["severity"])?.lowercased() {
                    severityCounts[severity, default: 0] += 1
                }
                if boolValue(offense["correctable"]) == true {
                    correctableCount += 1
                }
                if let copName = stringValue(offense["cop_name"]) {
                    appendUnique(sanitizedLabel(copName), to: &copLabels, limit: previewLimit)
                }
            }
        }

        guard offenseCount > 0 || !fileLabels.isEmpty else { return nil }

        let knownSeverities = ["fatal", "error", "warning", "convention", "refactor", "info"]
        let otherSeverityCount = severityCounts
            .filter { !knownSeverities.contains($0.key) }
            .map(\.value)
            .reduce(0, +)

        return ToolArtifactRuboCopJSONPreview(
            fileCount: files.count,
            offenseCount: offenseCount,
            fatalCount: severityCounts["fatal"] ?? 0,
            errorCount: severityCounts["error"] ?? 0,
            warningCount: severityCounts["warning"] ?? 0,
            conventionCount: severityCounts["convention"] ?? 0,
            refactorCount: severityCounts["refactor"] ?? 0,
            infoCount: severityCounts["info"] ?? 0,
            otherSeverityCount: otherSeverityCount,
            correctableCount: correctableCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            copPreviewLabels: copLabels
        )
    }

    private static func hasRuboCopReportShape(_ report: [String: Any]) -> Bool {
        guard report["files"] is [[String: Any]] else { return false }
        return report["metadata"] is [String: Any]
            || report.keys.contains("summary")
            || (report["files"] as? [[String: Any]] ?? []).contains(where: hasRuboCopFileShape)
    }

    private static func hasRuboCopFileShape(_ file: [String: Any]) -> Bool {
        guard stringValue(file["path"]) != nil,
              let offenses = file["offenses"] as? [[String: Any]]
        else {
            return false
        }
        return offenses.isEmpty || offenses.contains { offense in
            stringValue(offense["cop_name"]) != nil
                || stringValue(offense["severity"]) != nil
                || stringValue(offense["message"]) != nil
        }
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

    private static func boolValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            return number.boolValue
        case let string as String:
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
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
