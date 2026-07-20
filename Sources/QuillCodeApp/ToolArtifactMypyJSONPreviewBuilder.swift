import Foundation

enum ToolArtifactMypyJSONPreviewBuilder {
    static func mypyJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactMypyJSONPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              ["json", "jsonl"].contains(documentPreview.extensionLabel.lowercased()),
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
            let diagnostics = try decodeDiagnostics(from: data)
            return preview(
                from: diagnostics,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func decodeDiagnostics(from data: Data) throws -> [[String: Any]] {
        if let root = try? JSONSerialization.jsonObject(with: data, options: []),
           let diagnostics = root as? [[String: Any]] {
            return diagnostics
        }

        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return try text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                let lineData = Data(trimmed.utf8)
                return try JSONSerialization.jsonObject(with: lineData, options: []) as? [String: Any]
            }
    }

    private static func preview(
        from diagnostics: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactMypyJSONPreview? {
        guard !diagnostics.isEmpty, diagnostics.allSatisfy(hasMypyDiagnosticShape) else { return nil }

        var fileLabels: [String] = []
        var codeLabels: [String] = []
        var errorCount = 0
        var noteCount = 0
        var otherSeverityCount = 0

        for diagnostic in diagnostics {
            if let path = stringValue(diagnostic["file"]) {
                appendUnique(sanitizedPathLabel(path), to: &fileLabels, limit: previewLimit)
            }
            if let code = stringValue(diagnostic["code"]) {
                appendUnique(sanitizedLabel(code), to: &codeLabels, limit: previewLimit)
            }

            switch stringValue(diagnostic["severity"])?.lowercased() {
            case "error":
                errorCount += 1
            case "note":
                noteCount += 1
            default:
                otherSeverityCount += 1
            }
        }

        guard !fileLabels.isEmpty else { return nil }

        return ToolArtifactMypyJSONPreview(
            diagnosticCount: diagnostics.count,
            fileCount: uniqueCount(in: diagnostics, key: "file"),
            codeCount: uniqueCount(in: diagnostics, key: "code"),
            errorCount: errorCount,
            noteCount: noteCount,
            otherSeverityCount: otherSeverityCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            codePreviewLabels: codeLabels
        )
    }

    private static func hasMypyDiagnosticShape(_ diagnostic: [String: Any]) -> Bool {
        guard stringValue(diagnostic["file"]) != nil,
              stringValue(diagnostic["message"]) != nil,
              stringValue(diagnostic["severity"]) != nil
        else {
            return false
        }
        return numericValue(diagnostic["line"]) != nil
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
