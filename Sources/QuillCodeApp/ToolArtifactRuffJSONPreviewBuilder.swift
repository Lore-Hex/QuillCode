import Foundation

enum ToolArtifactRuffJSONPreviewBuilder {
    static func ruffJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactRuffJSONPreview? {
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
    ) -> ToolArtifactRuffJSONPreview? {
        guard !violations.isEmpty, violations.allSatisfy(hasRuffViolationShape) else { return nil }

        var fileLabels: [String] = []
        var ruleLabels: [String] = []
        var fixableCount = 0

        for violation in violations {
            if let filename = stringValue(violation["filename"]) {
                appendUnique(sanitizedPathLabel(filename), to: &fileLabels, limit: previewLimit)
            }
            if let code = stringValue(violation["code"]) {
                appendUnique(sanitizedLabel(code), to: &ruleLabels, limit: previewLimit)
            }
            if let fix = violation["fix"], !(fix is NSNull) {
                fixableCount += 1
            }
        }

        guard !fileLabels.isEmpty || !ruleLabels.isEmpty else { return nil }

        return ToolArtifactRuffJSONPreview(
            violationCount: violations.count,
            fileCount: uniqueFileCount(in: violations),
            ruleCount: uniqueRuleCount(in: violations),
            fixableCount: fixableCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            rulePreviewLabels: ruleLabels
        )
    }

    private static func hasRuffViolationShape(_ violation: [String: Any]) -> Bool {
        guard stringValue(violation["code"]) != nil,
              stringValue(violation["message"]) != nil,
              stringValue(violation["filename"]) != nil,
              let location = violation["location"] as? [String: Any]
        else {
            return false
        }
        return location.keys.contains("row") && location.keys.contains("column")
    }

    private static func uniqueFileCount(in violations: [[String: Any]]) -> Int {
        Set(violations.compactMap { stringValue($0["filename"]) }).count
    }

    private static func uniqueRuleCount(in violations: [[String: Any]]) -> Int {
        Set(violations.compactMap { stringValue($0["code"]) }).count
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
