import Foundation

enum ToolArtifactSemgrepJSONPreviewBuilder {
    static func semgrepJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactSemgrepJSONPreview? {
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
            guard let report = root as? [String: Any],
                  let results = report["results"] as? [[String: Any]]
            else {
                return nil
            }
            return preview(
                from: report,
                results: results,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(
        from report: [String: Any],
        results: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactSemgrepJSONPreview? {
        guard hasSemgrepReportShape(report),
              results.allSatisfy(hasSemgrepResultShape)
        else {
            return nil
        }

        var fileLabels: [String] = []
        var ruleLabels: [String] = []
        var errorSeverityCount = 0
        var warningSeverityCount = 0
        var infoSeverityCount = 0
        var otherSeverityCount = 0

        for result in results {
            if let path = stringValue(result["path"]) {
                appendUnique(sanitizedPathLabel(path), to: &fileLabels, limit: previewLimit)
            }
            if let checkID = stringValue(result["check_id"]) {
                appendUnique(sanitizedLabel(checkID), to: &ruleLabels, limit: previewLimit)
            }

            switch severity(in: result)?.uppercased() {
            case "ERROR":
                errorSeverityCount += 1
            case "WARNING":
                warningSeverityCount += 1
            case "INFO":
                infoSeverityCount += 1
            default:
                otherSeverityCount += 1
            }
        }

        return ToolArtifactSemgrepJSONPreview(
            findingCount: results.count,
            fileCount: uniqueCount(in: results, key: "path"),
            ruleCount: uniqueCount(in: results, key: "check_id"),
            errorSeverityCount: errorSeverityCount,
            warningSeverityCount: warningSeverityCount,
            infoSeverityCount: infoSeverityCount,
            otherSeverityCount: otherSeverityCount,
            errorCount: (report["errors"] as? [Any])?.count ?? 0,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            rulePreviewLabels: ruleLabels
        )
    }

    private static func hasSemgrepReportShape(_ report: [String: Any]) -> Bool {
        stringValue(report["version"]) != nil
            && (report["paths"] is [String: Any] || report["errors"] is [Any])
    }

    private static func hasSemgrepResultShape(_ result: [String: Any]) -> Bool {
        guard stringValue(result["check_id"]) != nil,
              stringValue(result["path"]) != nil,
              result["start"] is [String: Any],
              result["end"] is [String: Any],
              let extra = result["extra"] as? [String: Any],
              stringValue(extra["message"]) != nil
        else {
            return false
        }
        return severity(in: result) != nil
    }

    private static func severity(in result: [String: Any]) -> String? {
        guard let extra = result["extra"] as? [String: Any] else { return nil }
        return stringValue(extra["severity"])
    }

    private static func uniqueCount(in results: [[String: Any]], key: String) -> Int {
        Set(results.compactMap { stringValue($0[key]) }).count
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
