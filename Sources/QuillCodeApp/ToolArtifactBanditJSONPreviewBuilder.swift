import Foundation

enum ToolArtifactBanditJSONPreviewBuilder {
    static func banditJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactBanditJSONPreview? {
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
    ) -> ToolArtifactBanditJSONPreview? {
        guard !results.isEmpty,
              stringValue(report["generated_at"]) != nil || report["metrics"] is [String: Any],
              results.allSatisfy(hasBanditIssueShape)
        else {
            return nil
        }

        var fileLabels: [String] = []
        var testLabels: [String] = []
        var highSeverityCount = 0
        var mediumSeverityCount = 0
        var lowSeverityCount = 0
        var otherSeverityCount = 0
        var highConfidenceCount = 0
        var mediumConfidenceCount = 0
        var lowConfidenceCount = 0
        var otherConfidenceCount = 0

        for result in results {
            if let filename = stringValue(result["filename"]) {
                appendUnique(sanitizedPathLabel(filename), to: &fileLabels, limit: previewLimit)
            }
            if let testID = stringValue(result["test_id"]) {
                let testName = stringValue(result["test_name"])
                appendUnique(testLabel(id: testID, name: testName), to: &testLabels, limit: previewLimit)
            }

            switch stringValue(result["issue_severity"])?.uppercased() {
            case "HIGH":
                highSeverityCount += 1
            case "MEDIUM":
                mediumSeverityCount += 1
            case "LOW":
                lowSeverityCount += 1
            default:
                otherSeverityCount += 1
            }

            switch stringValue(result["issue_confidence"])?.uppercased() {
            case "HIGH":
                highConfidenceCount += 1
            case "MEDIUM":
                mediumConfidenceCount += 1
            case "LOW":
                lowConfidenceCount += 1
            default:
                otherConfidenceCount += 1
            }
        }

        guard !fileLabels.isEmpty || !testLabels.isEmpty else { return nil }

        return ToolArtifactBanditJSONPreview(
            issueCount: results.count,
            fileCount: uniqueCount(in: results, key: "filename"),
            testCount: uniqueCount(in: results, key: "test_id"),
            highSeverityCount: highSeverityCount,
            mediumSeverityCount: mediumSeverityCount,
            lowSeverityCount: lowSeverityCount,
            otherSeverityCount: otherSeverityCount,
            highConfidenceCount: highConfidenceCount,
            mediumConfidenceCount: mediumConfidenceCount,
            lowConfidenceCount: lowConfidenceCount,
            otherConfidenceCount: otherConfidenceCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            testPreviewLabels: testLabels
        )
    }

    private static func hasBanditIssueShape(_ result: [String: Any]) -> Bool {
        guard stringValue(result["filename"]) != nil,
              stringValue(result["issue_confidence"]) != nil,
              stringValue(result["issue_severity"]) != nil,
              stringValue(result["issue_text"]) != nil,
              stringValue(result["test_id"]) != nil,
              stringValue(result["test_name"]) != nil
        else {
            return false
        }
        return numericValue(result["line_number"]) != nil
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

    private static func numericValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = stringValue(value) {
            return Double(string)
        }
        return nil
    }

    private static func testLabel(id: String, name: String?) -> String {
        guard let name else { return sanitizedLabel(id) }
        return sanitizedLabel("\(id) \(name)")
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
