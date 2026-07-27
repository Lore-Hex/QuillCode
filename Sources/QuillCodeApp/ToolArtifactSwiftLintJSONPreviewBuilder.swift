import Foundation

enum ToolArtifactSwiftLintJSONPreviewBuilder {
    static func swiftLintJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactSwiftLintJSONPreview? {
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
            guard let violations = root as? [[String: Any]] else { return nil }
            return preview(
                from: violations,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(
        from violations: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactSwiftLintJSONPreview? {
        guard !violations.isEmpty, violations.allSatisfy(hasSwiftLintViolationShape) else { return nil }

        var fileLabels: [String] = []
        var ruleLabels: [String] = []
        var errorCount = 0
        var warningCount = 0
        var otherSeverityCount = 0

        for violation in violations {
            if let file = stringValue(violation["file"]) {
                appendUnique(sanitizedPathLabel(file), to: &fileLabels, limit: previewLimit)
            }
            if let rule = stringValue(violation["rule_id"]) ?? stringValue(violation["type"]) {
                appendUnique(sanitizedLabel(rule), to: &ruleLabels, limit: previewLimit)
            }

            switch stringValue(violation["severity"])?.lowercased() {
            case "error":
                errorCount += 1
            case "warning":
                warningCount += 1
            default:
                otherSeverityCount += 1
            }
        }

        guard !fileLabels.isEmpty else { return nil }

        return ToolArtifactSwiftLintJSONPreview(
            violationCount: violations.count,
            fileCount: uniqueCount(in: violations, key: "file"),
            ruleCount: uniqueRuleCount(in: violations),
            errorCount: errorCount,
            warningCount: warningCount,
            otherSeverityCount: otherSeverityCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            rulePreviewLabels: ruleLabels
        )
    }

    private static func hasSwiftLintViolationShape(_ violation: [String: Any]) -> Bool {
        guard stringValue(violation["file"]) != nil,
              stringValue(violation["reason"]) != nil,
              stringValue(violation["severity"]) != nil
        else {
            return false
        }
        return stringValue(violation["rule_id"]) != nil
            || stringValue(violation["type"]) != nil
            || numericValue(violation["line"]) != nil
    }

    private static func uniqueCount(in violations: [[String: Any]], key: String) -> Int {
        Set(violations.compactMap { stringValue($0[key]) }).count
    }

    private static func uniqueRuleCount(in violations: [[String: Any]]) -> Int {
        Set(violations.compactMap { stringValue($0["rule_id"]) ?? stringValue($0["type"]) }).count
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

    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
