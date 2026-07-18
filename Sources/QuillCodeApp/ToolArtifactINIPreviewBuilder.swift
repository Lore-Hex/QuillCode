import Foundation

enum ToolArtifactINIPreviewBuilder {
    static func iniPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactINIPreview? {
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
                  let text = String(data: data, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            let preview = preview(
                from: text,
                formatLabel: documentPreview.extensionLabel.uppercased(),
                fileSize: fileSize
            )
            return preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(
        from text: String,
        formatLabel: String,
        fileSize: Int
    ) -> ToolArtifactINIPreview {
        var sections: [String] = []
        var seenSections = Set<String>()
        var keyCount = 0
        var processedLines = 0
        var isTruncated = false

        for rawLine in text.split(whereSeparator: \.isNewline) {
            processedLines += 1
            if processedLines > lineLimit {
                isTruncated = true
                break
            }
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty,
                  !line.hasPrefix("#"),
                  !line.hasPrefix(";")
            else {
                continue
            }

            if let section = sectionLabel(from: line) {
                if seenSections.insert(section).inserted {
                    sections.append(section)
                }
                continue
            }

            if isKeyValueLine(line) {
                keyCount += 1
            }
        }

        let previewLabels = previewLabels(for: sections)
        return ToolArtifactINIPreview(
            formatLabel: formatLabel,
            sectionCount: sections.count,
            keyCount: keyCount,
            sectionPreviewLabel: previewLabel(for: sections),
            sectionPreviewLabels: previewLabels,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            isTruncated: isTruncated
        )
    }

    private static func sectionLabel(from line: String) -> String? {
        guard line.hasPrefix("["),
              let closingBracket = line.firstIndex(of: "]")
        else {
            return nil
        }
        let afterOpeningBracket = line.index(after: line.startIndex)
        guard afterOpeningBracket < closingBracket else {
            return "(empty section)"
        }
        return sanitizedLabel(String(line[afterOpeningBracket..<closingBracket]))
    }

    private static func isKeyValueLine(_ line: String) -> Bool {
        guard let delimiterIndex = line.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
            return false
        }
        let key = line[..<delimiterIndex].trimmingCharacters(in: .whitespaces)
        return !key.isEmpty
    }

    private static func previewLabel(for sections: [String]) -> String? {
        let visibleSections = previewLabels(for: sections)
        guard !visibleSections.isEmpty else { return nil }
        let remainder = sections.count - visibleSections.count
        return ([visibleSections.joined(separator: ", ")] + (remainder > 0 ? ["+\(remainder) more"] : []))
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func previewLabels(for sections: [String]) -> [String] {
        Array(sections.prefix(sectionPreviewLimit))
    }

    private static func sanitizedLabel(_ label: String) -> String {
        let collapsedWhitespace = label
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((collapsedWhitespace.isEmpty ? "(empty section)" : collapsedWhitespace).prefix(sectionCharacterLimit))
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

    private static let supportedExtensions: Set<String> = ["cfg", "conf", "ini"]
    private static let byteLimit = 64 * 1_024
    private static let lineLimit = 2_000
    private static let sectionPreviewLimit = 6
    private static let sectionCharacterLimit = 80
}
