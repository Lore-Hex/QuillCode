import Foundation

enum ToolArtifactJSONLinesPreviewBuilder {
    static func jsonLinesPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactJSONLinesPreview? {
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
            guard fileSize > 0 else { return nil }
            let data = try boundedData(from: fileURL, fileSize: fileSize)
            guard !data.contains(0),
                  let text = String(data: data, encoding: .utf8)
            else {
                return nil
            }
            let preview = try preview(
                from: text,
                extensionLabel: documentPreview.extensionLabel,
                fileSize: fileSize,
                isTruncated: fileSize > byteLimit
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func boundedData(from fileURL: URL, fileSize: Int) throws -> Data {
        if fileSize <= byteLimit {
            return try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return try handle.read(upToCount: byteLimit) ?? Data()
    }

    private static func preview(
        from text: String,
        extensionLabel: String,
        fileSize: Int,
        isTruncated: Bool
    ) throws -> ToolArtifactJSONLinesPreview {
        let nonemptyLines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !nonemptyLines.isEmpty else {
            throw PreviewError.empty
        }

        var observedKeys = Set<String>()
        for line in nonemptyLines.prefix(recordParseLimit) {
            let data = Data(line.utf8)
            let root = try JSONSerialization.jsonObject(with: data, options: [])
            if let object = root as? [String: Any] {
                observedKeys.formUnion(object.keys)
            }
        }

        let recordCountLabel = isTruncated
            ? "\(nonemptyLines.count)+ records"
            : "\(nonemptyLines.count) record\(nonemptyLines.count == 1 ? "" : "s")"
        let keys = observedKeys.sorted()
        return ToolArtifactJSONLinesPreview(
            formatLabel: extensionLabel.uppercased(),
            recordCountLabel: recordCountLabel,
            keyPreviewLabel: previewLabel(for: keys),
            keyPreviewLabels: previewLabels(for: keys),
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            isTruncated: isTruncated
        )
    }

    private static func previewLabel(for keys: [String]) -> String? {
        guard !keys.isEmpty else { return nil }
        let visibleKeys = keys.prefix(keyPreviewLimit)
        let labels = visibleKeys.map(sanitizedLabel)
        let remainder = keys.count - visibleKeys.count
        return ([labels.joined(separator: ", ")] + (remainder > 0 ? ["+\(remainder) more"] : []))
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func previewLabels(for keys: [String]) -> [String] {
        Array(keys.prefix(keyPreviewLimit)).map(sanitizedLabel)
    }

    private static func sanitizedLabel(_ key: String) -> String {
        let collapsedWhitespace = key
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "(empty key)" : collapsedWhitespace).prefix(keyCharacterLimit))
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

    private enum PreviewError: Error {
        case empty
    }

    private static let supportedExtensions: Set<String> = ["jsonl", "ndjson"]
    private static let byteLimit = 64 * 1_024
    private static let recordParseLimit = 20
    private static let keyPreviewLimit = 6
    private static let keyCharacterLimit = 80
}
