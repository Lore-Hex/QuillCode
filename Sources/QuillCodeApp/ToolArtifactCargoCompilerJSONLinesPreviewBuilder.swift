import Foundation

enum ToolArtifactCargoCompilerJSONLinesPreviewBuilder {
    static func cargoCompilerJSONLinesPreview(
        for value: String,
        kind: ToolArtifactKind
    ) -> ToolArtifactCargoCompilerJSONLinesPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              supportedExtensions.contains(documentPreview.extensionLabel.lowercased()),
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
            guard !data.contains(0),
                  let text = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            let records = try decodeRecords(from: text)
            return preview(
                from: records,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func decodeRecords(from text: String) throws -> [[String: Any]] {
        try text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> [String: Any]? in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return try JSONSerialization.jsonObject(with: Data(trimmed.utf8), options: []) as? [String: Any]
            }
    }

    private static func preview(
        from records: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactCargoCompilerJSONLinesPreview? {
        let diagnostics = records.compactMap(cargoDiagnostic)
        guard !diagnostics.isEmpty else { return nil }

        var fileLabels: [String] = []
        var codeLabels: [String] = []
        var errorCount = 0
        var warningCount = 0
        var noteCount = 0
        var helpCount = 0
        var otherLevelCount = 0

        for diagnostic in diagnostics {
            appendUnique(sanitizedPathLabel(diagnostic.file), to: &fileLabels, limit: previewLimit)
            if let code = diagnostic.code {
                appendUnique(sanitizedLabel(code), to: &codeLabels, limit: previewLimit)
            }

            switch diagnostic.level.lowercased() {
            case "error":
                errorCount += 1
            case "warning":
                warningCount += 1
            case "note":
                noteCount += 1
            case "help":
                helpCount += 1
            default:
                otherLevelCount += 1
            }
        }

        guard !fileLabels.isEmpty else { return nil }

        return ToolArtifactCargoCompilerJSONLinesPreview(
            diagnosticCount: diagnostics.count,
            fileCount: Set(diagnostics.map(\.file)).count,
            codeCount: Set(diagnostics.compactMap(\.code)).count,
            errorCount: errorCount,
            warningCount: warningCount,
            noteCount: noteCount,
            helpCount: helpCount,
            otherLevelCount: otherLevelCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            codePreviewLabels: codeLabels
        )
    }

    private static func cargoDiagnostic(from record: [String: Any]) -> CargoDiagnostic? {
        guard stringValue(record["reason"]) == "compiler-message",
              let message = record["message"] as? [String: Any],
              let level = stringValue(message["level"]),
              stringValue(message["message"]) != nil,
              let file = primarySpanFile(in: message)
        else {
            return nil
        }

        let code = (message["code"] as? [String: Any]).flatMap { stringValue($0["code"]) }
        return CargoDiagnostic(file: file, level: level, code: code)
    }

    private static func primarySpanFile(in message: [String: Any]) -> String? {
        guard let spans = message["spans"] as? [[String: Any]] else { return nil }
        if let primary = spans.first(where: { boolValue($0["is_primary"]) == true }),
           let file = stringValue(primary["file_name"]) {
            return file
        }
        return spans.compactMap { stringValue($0["file_name"]) }.first
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
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
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

    private struct CargoDiagnostic {
        var file: String
        var level: String
        var code: String?
    }

    private static let supportedExtensions: Set<String> = ["jsonl", "ndjson"]
    private static let byteLimit = 512 * 1_024
    private static let previewLimit = 6
    private static let characterLimit = 96
}
