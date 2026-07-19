import Foundation

enum ToolArtifactPylintJSONPreviewBuilder {
    static func pylintJSONPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactPylintJSONPreview? {
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
            guard let messages = root as? [[String: Any]] else { return nil }
            return preview(
                from: messages,
                byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize)
            )
        } catch {
            return nil
        }
    }

    private static func preview(
        from messages: [[String: Any]],
        byteSizeLabel: String?
    ) -> ToolArtifactPylintJSONPreview? {
        guard !messages.isEmpty, messages.allSatisfy(hasPylintMessageShape) else { return nil }

        var fileLabels: [String] = []
        var symbolLabels: [String] = []
        var fatalCount = 0
        var errorCount = 0
        var warningCount = 0
        var refactorCount = 0
        var conventionCount = 0
        var infoCount = 0
        var otherTypeCount = 0

        for message in messages {
            if let path = stringValue(message["path"]) {
                appendUnique(sanitizedPathLabel(path), to: &fileLabels, limit: previewLimit)
            }
            if let symbol = stringValue(message["symbol"]) {
                appendUnique(sanitizedLabel(symbol), to: &symbolLabels, limit: previewLimit)
            }

            switch stringValue(message["type"])?.lowercased() {
            case "fatal":
                fatalCount += 1
            case "error":
                errorCount += 1
            case "warning":
                warningCount += 1
            case "refactor":
                refactorCount += 1
            case "convention":
                conventionCount += 1
            case "info":
                infoCount += 1
            default:
                otherTypeCount += 1
            }
        }

        guard !fileLabels.isEmpty || !symbolLabels.isEmpty else { return nil }

        return ToolArtifactPylintJSONPreview(
            messageCount: messages.count,
            fileCount: uniqueCount(in: messages, key: "path"),
            symbolCount: uniqueCount(in: messages, key: "symbol"),
            fatalCount: fatalCount,
            errorCount: errorCount,
            warningCount: warningCount,
            refactorCount: refactorCount,
            conventionCount: conventionCount,
            infoCount: infoCount,
            otherTypeCount: otherTypeCount,
            byteSizeLabel: byteSizeLabel,
            filePreviewLabels: fileLabels,
            symbolPreviewLabels: symbolLabels
        )
    }

    private static func hasPylintMessageShape(_ message: [String: Any]) -> Bool {
        guard stringValue(message["type"]) != nil,
              stringValue(message["module"]) != nil,
              stringValue(message["message"]) != nil,
              stringValue(message["message-id"]) != nil,
              stringValue(message["path"]) != nil,
              stringValue(message["symbol"]) != nil
        else {
            return false
        }
        return numericValue(message["line"]) != nil
    }

    private static func uniqueCount(in messages: [[String: Any]], key: String) -> Int {
        Set(messages.compactMap { stringValue($0[key]) }).count
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
