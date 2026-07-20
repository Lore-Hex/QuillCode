import Foundation

enum ToolArtifactPHPStanJSONPreviewBuilder {
    static func phpstanJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPHPStanJSONPreview? {
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
    ) -> ToolArtifactPHPStanJSONPreview? {
        guard let files = report["files"] as? [String: Any],
              hasPHPStanTotals(report["totals"]),
              !files.isEmpty
        else {
            return nil
        }

        var fileLabels: [String] = []
        var identifierLabels: [String] = []
        var fileErrorCount = 0
        var ignorableCount = 0
        var nonIgnorableCount = 0

        for path in files.keys.sorted() {
            guard let value = files[path] else { continue }
            guard let fileReport = value as? [String: Any],
                  let messages = fileReport["messages"] as? [[String: Any]],
                  !messages.isEmpty,
                  messages.allSatisfy(hasPHPStanMessageShape)
            else {
                return nil
            }

            appendUnique(sanitizedPathLabel(path), to: &fileLabels, limit: previewLimit)
            fileErrorCount += messages.count
            for message in messages {
                if boolValue(message["ignorable"]) == true {
                    ignorableCount += 1
                } else {
                    nonIgnorableCount += 1
                }
                if let identifier = stringValue(message["identifier"]) {
                    appendUnique(sanitizedLabel(identifier), to: &identifierLabels, limit: previewLimit)
                }
            }
        }

        let generalErrorCount = (report["errors"] as? [Any])?.count ?? 0
        guard fileErrorCount > 0 || generalErrorCount > 0 else { return nil }

        return ToolArtifactPHPStanJSONPreview(
            errorCount: fileErrorCount + generalErrorCount,
            fileCount: files.count,
            identifierCount: uniqueIdentifierCount(in: files),
            generalErrorCount: generalErrorCount,
            ignorableCount: ignorableCount,
            nonIgnorableCount: nonIgnorableCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            identifierPreviewLabels: identifierLabels
        )
    }

    private static func hasPHPStanTotals(_ value: Any?) -> Bool {
        guard let totals = value as? [String: Any] else { return false }
        return numericValue(totals["errors"]) != nil
            && numericValue(totals["file_errors"]) != nil
    }

    private static func hasPHPStanMessageShape(_ message: [String: Any]) -> Bool {
        guard stringValue(message["message"]) != nil else { return false }
        return numericValue(message["line"]) != nil
            || stringValue(message["identifier"]) != nil
            || message.keys.contains("ignorable")
    }

    private static func uniqueIdentifierCount(in files: [String: Any]) -> Int {
        var identifiers = Set<String>()
        for value in files.values {
            guard let fileReport = value as? [String: Any],
                  let messages = fileReport["messages"] as? [[String: Any]]
            else { continue }
            for message in messages {
                if let identifier = stringValue(message["identifier"]) {
                    identifiers.insert(identifier)
                }
            }
        }
        return identifiers.count
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

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
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
