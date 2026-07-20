import Foundation

enum ToolArtifactStylelintJSONPreviewBuilder {
    static func stylelintJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactStylelintJSONPreview? {
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
    ) -> ToolArtifactStylelintJSONPreview? {
        guard !results.isEmpty, results.allSatisfy(hasStylelintResultShape) else { return nil }

        var warningCount = 0
        var errorCount = 0
        var parseErrorCount = 0
        var deprecationCount = 0
        var invalidOptionWarningCount = 0
        var sourceLabels: [String] = []
        var ruleLabels: [String] = []

        for result in results {
            if let source = stringValue(result["source"]) {
                appendUnique(sanitizedPathLabel(source), to: &sourceLabels, limit: previewLimit)
            }

            let warnings = result["warnings"] as? [[String: Any]] ?? []
            warningCount += warnings.count
            errorCount += warnings.filter { stringValue($0["severity"])?.lowercased() == "error" }.count
            parseErrorCount += (result["parseErrors"] as? [[String: Any]] ?? []).count
            deprecationCount += (result["deprecations"] as? [[String: Any]] ?? []).count
            invalidOptionWarningCount += (result["invalidOptionWarnings"] as? [[String: Any]] ?? []).count

            for warning in warnings {
                guard let rule = stringValue(warning["rule"]) else { continue }
                appendUnique(sanitizedLabel(rule), to: &ruleLabels, limit: previewLimit)
            }
        }

        return ToolArtifactStylelintJSONPreview(
            fileCount: results.count,
            warningCount: warningCount,
            errorCount: errorCount,
            parseErrorCount: parseErrorCount,
            deprecationCount: deprecationCount,
            invalidOptionWarningCount: invalidOptionWarningCount,
            byteSizeLabel: byteSizeLabel,
            sourcePreviewLabels: sourceLabels,
            rulePreviewLabels: ruleLabels
        )
    }

    private static func hasStylelintResultShape(_ result: [String: Any]) -> Bool {
        guard stringValue(result["source"]) != nil else { return false }
        return result["warnings"] is [[String: Any]]
            || result["parseErrors"] is [[String: Any]]
            || result["deprecations"] is [[String: Any]]
            || result["invalidOptionWarnings"] is [[String: Any]]
            || result.keys.contains("errored")
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
