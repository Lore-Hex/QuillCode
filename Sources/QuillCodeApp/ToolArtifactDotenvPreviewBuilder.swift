import Foundation

enum ToolArtifactDotenvPreviewBuilder {
    static func dotenvPreview(for value: String, kind: ToolArtifactKind) -> ToolArtifactDotenvPreview? {
        guard kind == .file,
              let documentPreview = ToolArtifactDocumentPreviewBuilder.documentPreview(for: value, kind: kind),
              documentPreview.kind == .data,
              documentPreview.extensionLabel.lowercased() == "env",
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
            let preview = preview(from: text, fileSize: fileSize)
            return preview.variableCount > 0 && preview.hasDisplayContent ? preview : nil
        } catch {
            return nil
        }
    }

    private static func preview(from text: String, fileSize: Int) -> ToolArtifactDotenvPreview {
        var keys: [String] = []
        var seenKeys = Set<String>()
        var variableCount = 0
        var exportedVariableCount = 0
        var processedLines = 0
        var isTruncated = false

        for rawLine in text.split(whereSeparator: \.isNewline) {
            processedLines += 1
            if processedLines > lineLimit {
                isTruncated = true
                break
            }
            guard let assignment = assignment(from: String(rawLine)) else { continue }
            variableCount += 1
            if assignment.isExported {
                exportedVariableCount += 1
            }
            if seenKeys.insert(assignment.key).inserted {
                keys.append(assignment.key)
            }
        }

        let previewLabels = previewLabels(for: keys)
        return ToolArtifactDotenvPreview(
            variableCount: variableCount,
            exportedVariableCount: exportedVariableCount,
            keyPreviewLabel: previewLabel(for: keys),
            keyPreviewLabels: previewLabels,
            byteSizeLabel: ToolArtifactByteSizeFormatter.label(for: fileSize),
            isTruncated: isTruncated
        )
    }

    private static func assignment(from rawLine: String) -> (key: String, isExported: Bool)? {
        var line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        var isExported = false
        if line.hasPrefix("export ") {
            isExported = true
            line = line.dropFirst("export ".count).trimmingCharacters(in: .whitespaces)
        }

        guard let delimiterIndex = line.firstIndex(of: "=") else { return nil }
        let rawKey = line[..<delimiterIndex].trimmingCharacters(in: .whitespaces)
        guard isValidKey(rawKey) else { return nil }
        return (String(rawKey.prefix(keyCharacterLimit)), isExported)
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first,
              first == "_" || first.isLetter
        else {
            return false
        }
        return key.allSatisfy { character in
            character == "_" || character.isLetter || character.isNumber
        }
    }

    private static func previewLabel(for keys: [String]) -> String? {
        let visibleKeys = previewLabels(for: keys)
        guard !visibleKeys.isEmpty else { return nil }
        let remainder = keys.count - visibleKeys.count
        return ([visibleKeys.joined(separator: ", ")] + (remainder > 0 ? ["+\(remainder) more"] : []))
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private static func previewLabels(for keys: [String]) -> [String] {
        Array(keys.prefix(keyPreviewLimit))
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

    private static let byteLimit = 64 * 1_024
    private static let lineLimit = 2_000
    private static let keyPreviewLimit = 8
    private static let keyCharacterLimit = 80
}
