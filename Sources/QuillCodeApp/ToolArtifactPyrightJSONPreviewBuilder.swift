import Foundation

enum ToolArtifactPyrightJSONPreviewBuilder {
    static func pyrightJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPyrightJSONPreview? {
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
                  let diagnostics = report["generalDiagnostics"] as? [[String: Any]]
            else { return nil }
            return preview(
                from: diagnostics,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(
        from diagnostics: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactPyrightJSONPreview? {
        guard !diagnostics.isEmpty, diagnostics.allSatisfy(hasPyrightDiagnosticShape) else { return nil }

        var fileLabels: [String] = []
        var ruleLabels: [String] = []
        var errorCount = 0
        var warningCount = 0
        var informationCount = 0
        var otherSeverityCount = 0

        for diagnostic in diagnostics {
            if let file = stringValue(diagnostic["file"]) {
                appendUnique(sanitizedPathLabel(file), to: &fileLabels, limit: previewLimit)
            }
            if let rule = stringValue(diagnostic["rule"]) {
                appendUnique(sanitizedLabel(rule), to: &ruleLabels, limit: previewLimit)
            }

            switch stringValue(diagnostic["severity"])?.lowercased() {
            case "error":
                errorCount += 1
            case "warning":
                warningCount += 1
            case "information":
                informationCount += 1
            default:
                otherSeverityCount += 1
            }
        }

        guard !fileLabels.isEmpty else { return nil }

        return ToolArtifactPyrightJSONPreview(
            diagnosticCount: diagnostics.count,
            fileCount: uniqueCount(in: diagnostics, key: "file"),
            ruleCount: uniqueCount(in: diagnostics, key: "rule"),
            errorCount: errorCount,
            warningCount: warningCount,
            informationCount: informationCount,
            otherSeverityCount: otherSeverityCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            rulePreviewLabels: ruleLabels
        )
    }

    private static func hasPyrightDiagnosticShape(_ diagnostic: [String: Any]) -> Bool {
        guard stringValue(diagnostic["file"]) != nil,
              stringValue(diagnostic["message"]) != nil,
              stringValue(diagnostic["severity"]) != nil,
              diagnostic["range"] is [String: Any]
        else {
            return false
        }
        return true
    }

    private static func uniqueCount(in diagnostics: [[String: Any]], key: String) -> Int {
        Set(diagnostics.compactMap { stringValue($0[key]) }).count
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
